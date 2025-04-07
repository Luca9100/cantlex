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
    dol <- tibble(law = lol, title = NA, abbreviation = NA) %>% 
      mutate(law = str_replace_all(law, "/", "%2F"))
    
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
    
    write_rds(dol, file = paste0("dataframe_of_laws/dataframe_of_laws_", canton_abbreviation, "_", language, ".rds"))
  }
}


# List all .rds files in the directory
rds_files <- list.files(path = "dataframe_of_laws", 
                        pattern = "\\.rds$", full.names = TRUE)

combined_df <- map_dfr(rds_files, ~ {
  df <- readRDS(.x)
  file_name <- basename(.x)
  canton <- str_extract(file_name, "(?<=dataframe_of_laws_)[a-z]{2}")
  language <- str_extract(file_name, "[a-z]{2}(?=\\.rds$)")
  df %>%
    mutate(file_name = file_name, canton = canton, language = language)
}) %>% 
  mutate(url = str_replace(url, "chde/", "ch/app/de/"),
         url = str_replace(url, "chfr/", "ch/app/fr/"),
         url = str_replace(url, "chit/", "ch/app/it/"),
         url = str_replace(url, "chrm/", "ch/app/rm/"),
         canton = str_to_upper(canton)) %>% 
  select(abbreviation, url, title, canton, language)

# openxlsx::write.xlsx(combined_df, file = "combined_df.xlsx")

zurich <- fromJSON("Zurich/zurich_laws_output.json") %>% 
  as_tibble()

bind_rows(combined_df,
          zurich) %>% 
  toJSON(pretty = TRUE) %>% 
  write(file = "abbreviations.json")

