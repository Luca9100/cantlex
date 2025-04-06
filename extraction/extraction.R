# Crawler to extract content from gr-lex.gr.ch 
# (or other Sitrox/Lexworks-based collections of law)
# Florian Geering, 20 November 2024

#    gr-lex uses a single-page application (SPA) framework that dynamically 
# rewriting the current web page with new data from the web server, 
# instead of the default method of loading entire new pages.
#    On one hand, this makes scraping the website content harder, as common crawlers 
# do not execute JavaScript, and therefore, new content is not loaded.
# On the other hand, the dynamically loaded new data is often passed through a
# JSON API, which can be used to extract data in a more structured format.

library(tidyverse)
library(progress)
library(httr)
library(jsonlite)

language <- "rm"  # de, rm, it

# Extract list of laws
lol_url <- paste0("https://www.gr-lex.gr.ch/api/", language, "/texts_of_law/lightweight_index")
lol_response <- GET(lol_url)
lol_data <- fromJSON(content(lol_response, "text"))
lol <- map(lol_data, ~ .x$systematic_number) %>% unlist() %>% unname()

# Create dataframe of laws
dol <- tibble(law = lol, title = NA, abbreviation = NA)

pb <- progress_bar$new(
  format = "[:bar] Extracting :current of :total, :eta remaining",
  total = nrow(dol), clear = FALSE, width= 60)

for (i in 1:nrow(dol)) {
  url <- paste0("https://www.gr-lex.gr.ch/api/", language, "/texts_of_law/", dol$law[i])
  response <- GET(url)
  data <- fromJSON(content(response, "text"))
  
  dol$title[i] <- data$text_of_law$title
  dol$abbreviation[i] <- data$text_of_law$abbreviation
  
  rm(data)
  pb$tick()
}

write_rds(dol, file = paste0("dol_", language, ".rds"))

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
