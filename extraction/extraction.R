# Crawler to extract content from Sitrox

library(tidyverse)
library(progress)
library(httr)
library(jsonlite)

list_of_cantons <- fromJSON("extraction/cantons.json") %>% 
  as_tibble() %>% 
  mutate(canton = str_to_lower(canton),
         base_url = str_extract(url, "^.*(?=/app/)"),
         languages = str_to_lower(languages))


# Loop through cantons
for (i in 1:nrow(list_of_cantons)) {
  base_url <- list_of_cantons$base_url[i]
  canton_abbreviation <- list_of_cantons$canton[i]
  
  languages <- list_of_cantons$languages[i] %>% 
    str_split(", ") %>% 
    unlist()
  
  # Loop through language versions
  for (language in languages) {
    lol_url <- paste0(base_url, "/api/", language, "/texts_of_law/lightweight_index")
    lol_response <- GET(lol_url)
    lol_data <- fromJSON(content(lol_response, "text"))
    lol <- map(lol_data, ~ .x$systematic_number) %>% unlist() %>% unname()
    
    # Create dataframe of laws
    dol <- tibble(law = lol, title = NA, abbreviation = NA)
    
    pb <- progress_bar$new(
      format = "[:bar] Extracting :current of :total, :eta remaining",
      total = nrow(dol), clear = FALSE, width= 60)
    
    for (i in 1:nrow(dol)) {
      url <- paste0(base_url, "/api/", language, "/texts_of_law/", dol$law[i]) %>% 
        str_replace_all(pattern = " ", replacement = "%20")
      response <- GET(url)
      data <- fromJSON(content(response, "text"))
      
      dol$title[i] <- data$text_of_law$title
      dol$abbreviation[i] <- data$text_of_law$abbreviation
      
      rm(data)
      pb$tick()
    }
    
    dol <- dol %>% 
      mutate(url = paste0(base_url, "/app/", language, "/texts_of_law/", law))
    
    write_rds(dol, file = paste0("dataframe_of_laws_", canton_abbreviation, "_", language, ".rds"))
  }
}


list_of_dataframes <- list.files("dataframe_of_laws/")

# List all .rds files in the directory
rds_files <- list.files(path = "dataframe_of_laws", 
                        pattern = "*.rds", full.names = TRUE)

# Read and combine all .rds files into a single dataframe using tidyverse functions
combined_df <- rds_files %>%
  map_df(readRDS) %>% 
  mutate(url = str_replace(url, "chde/", "ch/app/de/"),
         url = str_replace(url, "chfr/", "ch/app/fr/"),
         url = str_replace(url, "chit/", "ch/app/it/"),
         url = str_replace(url, "chrm/", "ch/app/rm/"))

openxlsx::write.xlsx(combined_df, 
                     file = "combined_df.xlsx")


dol_de <- read_rds("dol_de.rds") %>% 
  mutate(abbreviation = if_else(law == "110.100", "KV", abbreviation)) %>% 
  separate_rows(abbreviation, sep = "[,;]") %>% 
  mutate(abbreviation = str_trim(abbreviation),
         language = "de")

dol_rm <- read_rds("dol_rm.rds") %>% 
  separate_rows(abbreviation, sep = "[,;]") %>% 
  mutate(abbreviation = str_trim(abbreviation),
         language = "rm") %>% 
  mutate(abbreviation = if_else(abbreviation != "", 
                                paste(language, abbreviation), NA))

dol_it <- read_rds("dol_it.rds") %>% 
  separate_rows(abbreviation, sep = "[,;]") %>% 
  mutate(abbreviation = str_trim(abbreviation),
         language = "it") %>% 
  mutate(abbreviation = if_else(abbreviation != "", 
                                paste(language, abbreviation), NA))

dol_de2 <- dol_de %>%
  bind_rows(  # One-word titles become abbreviations
    dol_de %>%
      filter(str_count(title, "\\s") == 0) %>%
      mutate(abbreviation = title)
  ) %>%
  bind_rows(  # Two-word "Kantonales?" titles also become abbreviations
    dol_de %>%
      filter(str_detect(title, "^Kantonales?\\s[A-Za-zäöü]+$")) %>%
      mutate(abbreviation = str_remove(title, "Kantonales? "))  # Two-word titles become abbreviations
  ) %>%
  bind_rows(  # Two-word "Kantonales?" titles also become abbreviations without "kantonales"
    dol_de %>%
      filter(str_detect(title, "^Kantonales?\\s[A-Za-zäöü]+$")) %>%
      mutate(abbreviation = title)  # Keep full abbreviation
  ) %>%
  bind_rows(  # Two-word "Kantonales?" abbreviations also become abbreviations without "kantonales"
    dol_de %>%
      filter(str_detect(abbreviation, "^Kantonales?\\s[A-Za-zäöü]+$")) %>%
      mutate(abbreviation = str_remove(abbreviation, "Kantonales? "))
  )

dol3 <- bind_rows(dol_de2, dol_rm, dol_it) %>% 
  arrange(law) %>% 
  mutate(abbreviation = na_if(abbreviation, ""),  # Remove empty strings
         abbreviation_lower = str_to_lower(abbreviation),  # Turn into lowercase
         url = paste0("https://www.gr-lex.gr.ch/app/", language, "/texts_of_law/", law)) %>%  # Create URLs
  filter(is.na(abbreviation) == FALSE)

dol3 %>% 
  select(abbreviation_lower, url) %>% 
  bind_rows(tibble(abbreviation_lower = c("zgb", "lol"),
                   url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
            tibble(abbreviation_lower = c("plattner", "pla"),
                   url = "https://doi.org/10.38107/021"),
            tibble(abbreviation_lower = c("iktv"),
                   url = "https://www.gr-lex.gr.ch/app/de/texts_of_law/170.500")) %>% 
  toJSON(pretty = TRUE) %>% 
  write(file = "abbreviations.json")
