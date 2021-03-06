library(shiny)
library(tidyverse)
library(gt)
library(dplyr)
library(ggplot2)
library(lubridate)
library(janitor)
library(shinyWidgets)
library(shinythemes)
library(ggthemes)
library(maps)
library(leaflet)
library(plotly)
library(DT)
library(broom)

# Read in Data

# Data from Wonder CDC

death_by_year_and_state <- read_rds("death_by_year_and_state.rds")

# Read in treatment locations

treatment_locations <- read_rds("treatment_locations.rds")

# This commented out data was too large to fit into the published app

# state_pop <- read_rds("state_pop.rds")

# us_state <- map_data("state") %>%
#   rename(state_full = region)

# Data from https://simplemaps.com/data/us-cities used later in map data

longlatinfo <- read_rds("longlatinfo.rds")

# Joining all of the longitude latitude info to treatment locations and looking
# at just Massachusetts.

treatment_locations_map_mas <- treatment_locations %>%
  left_join(longlatinfo, by = c("City", "State")) %>%
  filter(State == "MA") %>%
  drop_na()

# Read in county info

counties <- read_rds("counties.rds")

# Looking at the deaths per county in Massachusetts

madeathbycounty <- read_rds("madeathbycounty.rds")

# Looking at county population for per capita calcs

countypop <- read_rds("countypop.rds")

# Join opioid deaths by county w county info

madeathbycountywlonglat <- madeathbycounty %>%
  left_join(counties, by = "Municipality")

# Cleaning up the data to look only at the info we want and look at deaths per
# county/time period

madeathbycountywlonglat <- madeathbycountywlonglat %>%
  select(County,
         `Confirmed Opioid Related Death Count 2001-2005`,
         `Confirmed Opioid Related Death Count 2006-2010`,
         `Confirmed Opioid Related Death Count 2011-2015`,
         `latitude`,
         `longitude`,
         `Municipality`) %>%
  distinct(Municipality, .keep_all= TRUE) %>%
  na.omit() %>%
  rename(subregion = County) %>%
  mutate(subregion = tolower(subregion)) %>%
  group_by(subregion) %>%
  mutate(total_deaths_2001.5 = 
           sum(`Confirmed Opioid Related Death Count 2001-2005`)) %>%
  mutate(total_deaths_2006.10 = 
           sum(`Confirmed Opioid Related Death Count 2006-2010`)) %>%
  mutate(total_deaths_2011.15 = 
           sum(`Confirmed Opioid Related Death Count 2011-2015`)) %>%
  distinct(subregion, .keep_all= TRUE)

# US County info for the maps

us_county <- map_data("county") %>%
  filter(region == "massachusetts")

# Poverty by County Info- may use later for multifactor regression

povertybycounty <- read_rds("povertybycounty.rds")

# Join all mass info

full_data <- us_county %>%
  left_join(madeathbycountywlonglat, by = "subregion") %>%
  left_join(countypop, by = "subregion") %>%
  left_join(povertybycounty, by = "subregion") %>%
  mutate(percap_2001.5 = total_deaths_2001.5/Pop) %>%
  mutate(percap_2006.10 = total_deaths_2006.10/Pop) %>%
  mutate(percap_2011.15 = total_deaths_2011.15/Pop)

# How opioid deaths differ by age

ageopioidmodel <- read_rds("ageopioidmodel.rds")

# How opioid deaths differ by race

raceopioidmodel <- read_rds("raceopioidmodel.rds")

# Join the two above models for easy use in shiny

ageandracemodel <- ageopioidmodel %>%
  na.omit() %>%
  full_join(raceopioidmodel, by = "year") %>%
  rename(deathsbyage = number_of_deaths) %>%
  rename(deathsbyrace = opioid_deaths)

# Number of deaths by cardiovasc or cancer vs opioids

deathsbycommondiseases <- read_rds("deathsbycommondiseases.rds")

# pivotting data for easy ggplotting by disease

totaldeathsbycommondiseases <- deathsbycommondiseases %>%
  select(Year, `Deaths by Cancer`, `Deaths by Drug Overdose`, 
         `Deaths by CVD`) %>%
  pivot_longer(.,
               cols = starts_with("Deaths by"),
               names_prefix = "Deaths by",
               values_to = "Deaths") %>%
  rename(`Cause of Death` = name)

# similar to above except with proportions compared to 1999 amounts

propdeathsbycommondiseases <- deathsbycommondiseases %>%
  select(Year, `Proportion of 1999 Deaths by Cancer`,
             `Proportion of 1999 Deaths by Drugs`,
             `Proportion of 1999 Deaths by CVD`) %>%
  rename(`Proportion of 1999 Deaths by Drug Overdose` = 
           `Proportion of 1999 Deaths by Drugs`) %>%
  pivot_longer(., cols = starts_with("Proportion of"), 
               names_prefix = "Proportion of 1999 Deaths by", 
               values_to = "Prop.Deaths") %>%
  rename(`Cause of Death` = name)

# comparing opioid rates between mass and us

mavsus_death <- read_rds("mavsus_death.rds")

# getting rid of dates where not complete info is present

mavsus_death <- mavsus_death %>%
  group_by(Geography) %>%
  filter (Year != "2015") %>%
  filter (Year != "1999") %>%
  rename(deathperhundredthousand =
           `Age-Adjusted Opioid-Related Death Rate per 100,000 People`)

ui <- navbarPage(theme = shinytheme("flatly"),
                 "Opioid Trends Across the United States",
                 tabPanel("United States Opioid Data",
                        h1("Opioid Deaths in America"),
                        h3("Comparing Deaths from 
                           Opioid Overdose to Deaths from the Leading Causes of 
                           Death in America"),
                        fixedRow(column(7, plotlyOutput("commondiseases", 
                                              height = "100%"), inline = TRUE),
                        column(3, offset = 1,           
                        p("The graph to the left shows CDC data for the number 
                        of deaths per year for the two top leading causes of 
                        death in the United States: heart disease or 
                        cardiovascular disease (CVD) and cancer. Simultaneously, 
                        I have graphed the number of deaths per year caused by 
                        opioid overdoses in the United States. While this graph 
                        may make it look like opioids do not have as great a 
                        toll on the United States as other diseases like cancer 
                        and cardiovascular disease, just because fewer people 
                        are affected does not mean the issue is less important."
                          ))),
                        br(),
                        h3("Comparing Deaths from Opioid Overdose to Deaths 
                           from the Leading Causes of Death in America 
                           (Normalized to 1990)"),
                        fixedRow(column(7, plotlyOutput("propcommondiseases", 
                        height = "100%", width = "100%"), inline = TRUE),        
                        column(3, offset = 1,  
                        p("In fact, if we normalize the number of deaths due to
                                   opioid use to those seen in 1990 as seen to 
                                   the left, we see the greatest proportion 
                                   change in deaths by opioid overdose compared 
                                   to cancer and cardiovascular disease as shown 
                                   below. Thus, even though we are slowly making 
                                   the changes needed to curtail cancer and 
                                   cardiovascular disease deaths, we are still 
                                   seeing sharp increases in death by
                                   opioid overdose."))),
                                   fluidPage(
                  h3("Drug Overdoses Per Capita by State Over Time"),
                  sliderTextInput("Year", "Year", 
                            from_min = 1998,
                            from_max =2018,
                            choices = levels(
                              as.factor(death_by_year_and_state$Year))),
                  fixedRow(column(7, plotOutput("overdose_counts"),
                                  inline = TRUE),
                column(3, offset = 1,
                p("We cannot assume that the distribution of opioid overdose 
                deaths per capita differs is uniform. There is certainly 
                variation based on state.The graph to the left shows how opioid 
                deaths per capita changed between 1998 and 2018. Some states 
                such as West Virginia have undergone immense changes in opioid 
                deaths per capita over the past 20 years, beginning with some of 
                the lowest death rates in 1998 and rising to have the highest 
                state death rate per capita in 2018.")))),
                br(),
                br(),
                br(),
                br(),
                br(),
                br(),
                h3("Distribution of Opioid Treatment Centers Per Capita in 2020"),
                fixedRow(column(7,imageOutput("treatment_centers_per_capita"),
                                inline = TRUE),
                column(3, offset = 1,
                p("Unfortunately, the distribution of treatment centers per 
                capita does not match up with the number of opioid deaths per 
                capita. Even if we just compare 2018 data, we will see that 
                states like New Hampshire have few opioid treatment centers 
                despite having some of the highest rates of opioid deaths per 
                capita. Furthermore, treatment centers seem to be concentrated 
                on the East of the country. Please note that the data for 
                treatment centers used to create the map to the left is more 
                recent than the most recent opioid death data."))
               )),
tabPanel("Massachusetts Opioid Data",
         h1("Opioid Deaths in Massachusetts"),
         h3("Comparison of Death Rates between Massachusetts and the 
            United States Between the Years of 2000 and 2014"),
             fixedRow(column(7,  plotlyOutput("madeathrates", height = "100%")),
                      column(3, offset = 1, p("The graph to the left, created 
                      using data from chapter55.digital.mass.gov shows that on 
                      average, the rate of opioid deaths per year in 
                      Massachusetts is higher than that of the United States. 
                      Despite efforts at expanding healthcare (for example, 
                      through Romneycare), opioid deaths stay consistently 
                      higher than the national average"))),
                h3("Opioid Deaths in Massachusetts by County over Time"),
         br(),
                # create drop down for user selecting time period
                
              fixedRow(column(7,  sidebarPanel(
                  selectInput("plot_type", 
                              label = h3("Select a time period"),
                              choices = c("2001-2005", "2006-2010", 
                                          "2011-2015"))),
                mainPanel(
                  plotOutput("plot_1"))),
                column(3, offset = 1, p("The graph to the left shows the 
                distribution of opioid deaths per capita across the counties of 
                Massachusetts for three different time periods between 2000 and 
                2015. Having looked at the data for total opioid deaths 
                (not per capita), I noticed that deaths seem to be concentrated in 
                Middlesex county, 
                although this makes sense given the high population of Middlesex. 
                Thus, in order to better demonstrate the distribution of deaths, 
                I chose to map the total deaths per capita by county."))),
                h3("Distribution of Opioid Treatment Centers Across 
                   Massachusetts"),
                fixedRow(column(7, fluidPage(
                  leafletOutput("masstreat"))),
                column(3, offset = 1, p("Similar to what we saw with the graph 
                of the entire United States, treatment centers are not 
                distributed based on the locations of the greatest number of 
                deaths per capita. Here, we see a high concentration of 
                treatment centers in the northeast corner of the state and in 
                the west rather than in the southwest, where Massachusetts 
                experiences the highest rates of opioid deaths.")))),
tabPanel("Model",
         h1("Model"),
         fixedRow(sidebarPanel(
           helpText("Choose a factor to see how opioid deaths change over time 
                    based on age and race."),
           selectInput("typeoffactor", 
                       label = h3("Select a factor"),
                       choices = c("Age", "Race"))),
         mainPanel(
           plotOutput("ageandrace"))),
          p("The models above demonstrate how opioid deaths have changed over 
          time based on age group and race. Based on age group data, it looks 
          like the total number of opioid deaths amongst people in the age 
          groups of 25-34, 35-44, and 45-54 are similar. However, the numbers 
          are increasing at the fastest rate amongst people between the ages of 
          25 and 34 as communicated by the highest coefficient.Thus, we must 
          focus on addressing issues pertaining to this group. Examining the 
          race data, it looks as though individuals are white at worst affected 
          by the opioid crisis, with both the highest number of deaths amongst 
          this group, in addition to the greatest rate of increase in deaths 
          amongst these individuals."),
         br(),
         br(),
         sidebarPanel(
           selectInput("Age Group", 
                       label = h3("Select an Age Range"),
                       choices = c("0-24", "25-34", "35-44", "45-54", "55+"))),
         mainPanel(
           DTOutput("coefage")),
         br(),
         br(),
         sidebarPanel(
           selectInput("Race", 
                       label = h3("Select a Category of Race"),
                       choices = c("White, Non-Hispanic", "Black, Non-Hispanic", 
                                   "Hispanic"))),
         mainPanel(
           DTOutput("coefrace"))),
         tabPanel("About",
                  imageOutput("pills"),
                  br(),
                  br(),
                  h2("Visualizing the Effects of Opioids Across the United States", align = "center"),
                  h4(em("An Analysis of Opioid Death Distribution"), align = "center"),
                  br(),
                  div(),
                  column(9,
                         h3("Background"),
                         p("Opioids have been prescribed for pain management for 
                         many decades, although they are effective at treating 
                         acute, not chronic pain. In treating chronic pain, 
                         opioids can be more harmful than useful. Opioids are 
                         cheap, but have high rates of addiction and can lead to 
                        dependence and ultimately death from overdose.Since the 
                        1990s, the United States has experienced a crisis 
                        created by overprescription of opioids. Thousands die 
                        yearly from uncontrollable overuse."),
                         
                         p("The plan for this project is to examine the 
                                   distribution of opioid deaths across states
                                   over the past twenty years. Having looked at 
                                   this data, I also sought to look at the 
                                   distribution of treatment centers to see if 
                                   the treatment center distribution matches up 
                                   with opioid death distribution: are the 
                                   states that need the most attention getting 
                                   the most attention?"),
                         
                         p("Following this, I analyzed the data for 
                                   the state nearest and dearest to our hearts, 
                                   Massachusetts. How does the distribution 
                                   of opioid deaths in Massachusetts look and 
                                   how are treatment centers distributed 
                                   according to deaths per capita in 
                                   different counties?"),
                         
                         p("Finally, I sought to create a model between factors 
                         of interest such as age and ethnicity and increases in 
                           opioid deaths over the past twenty years."),
                         h3("The Data"),
                         p("Data concerning the entire United States came from 
                         the CDC's Wonder Archive. Massachusetts-specific data 
                         came from chapter55.digital.mass.gov. The image above 
                           came from",
                           a("here",
                           href = 
                           "https://patientengagementhit.com/features/reconciling-the-opioid-crisis-with-delivering-quality-patient-experience",),
                         p("My project code can be found on my",
                           a("GitHub",
                             href = 
                "https://github.com/suruchiramanujan/Opioid-Crisis-Explore",)),
                         h3("About Me"),
                         p("My name is Suruchi Ramanujan and I am a senior in 
                         Quincy House studying Molecular and Cellular Biology.
                         In the future, I would like to optimize data usage in 
                         the health fields."),
                         p("You can reach me at ",
                           a("suruchi_ramanujan@college.harvard.edu",
                  href = "mailto: suruchi_ramanujan@college.harvard.edu",),
                           "or on ",
                           a("LinkedIn",
          href = "https://www.linkedin.com/in/suruchi-ramanujan-791007115/")))
)))
server <- function(input, output, session) {
  
  # plotting year vs opioid death rate per capita/10000 across U.S.
  
    output$overdose_counts <- renderPlot({
      death_by_year_and_state %>%
      filter(Year == input$Year) %>%
        ggplot(aes(x = long, y = lat,
                             fill = `Crude Rate`, group = group)) + 
        geom_polygon(color = "gray90", size = 0.05) + 
        theme_map() +
        scale_fill_gradient(name = "Overdose Deaths Per Capita/100,000",
                            low = "white", high = "#CB454A",
                            breaks = c(0,5,10,15,20,25,30,35,40,45,50)) +
        guides(fill = guide_legend(nrow = 1)) + 
        theme(legend.position = "bottom")
      }, width = 720,
      height = 540)
    
    output$plot_1 <- renderPlot({
      
    # plotting year range vs opioid death rate per capita in counties in MA.
      
    ggplot(data = full_data,
           mapping = aes(x = long, y = lat,
                         fill = case_when(
                           input$plot_type == "2001-2005" ~ percap_2001.5,
                           input$plot_type == "2006-2010" ~ percap_2006.10,
                           input$plot_type == "2011-2015" ~ percap_2011.15),
                         group = group)) +
      geom_polygon(color = "gray90", size = 0.05) +
      theme_map() +
      labs(names = "Number of Opioid Deaths per Capita/100,000") +
      scale_fill_gradient(name = "Number of Opioid Deaths per Capita/100,000",
                          low = "white", high = "#CB454A",
                          breaks = c(0,20,40,60,80,100)) +
      guides(fill = guide_legend(nrow = 1)) +
      theme(legend.position = "bottom")
   })
  
    # plotting year range vs opioid death rate per 10000 in MA vs US.
    
    output$madeathrates <- renderPlotly({
     map_2 <- ggplot(mavsus_death, aes(x = Year, 
                  y = as.numeric(deathperhundredthousand), color = Geography)) +
        geom_line() +
        scale_color_viridis_d() +
        theme_classic() +
        labs(x = "Year",
             y = "Deaths per 100,000") +
        geom_point()

     map_2 <- ggplotly(map_2) %>%
       layout(showlegend=T)
    })
  
    # plotting deaths by different types of disease(most common ones vs drug
    # overdose in u.s.)
    
    output$commondiseases <- renderPlotly({
     plot_2 <- ggplot(totaldeathsbycommondiseases, aes(x = Year, y = Deaths, 
                                                    color = `Cause of Death`)) +
        geom_line() +
        scale_color_viridis_d() +
        theme_classic() +
        labs(x = "Year",
             y = "Total Number of Deaths in the United States") +
        geom_point()
    
     # plotly + keep legend
     
     plot_2 <- ggplotly(plot_2) %>%
       layout(showlegend=T)
      
      })
    
    # plotting deaths by different types of disease(most common ones vs drug
    # overdose in u.s.) by comparing 1990 numbers to numbers in years after
    
    output$propcommondiseases <- renderPlotly({
    plot_3 <- ggplot(propdeathsbycommondiseases, aes(x = Year, y = Prop.Deaths, 
                                                  color = `Cause of Death`)) +
        geom_line() +
        scale_color_viridis_d() +
        theme_classic() +
        labs(color = "Cause of Death",
            x = "Year",
             y = "Proportion of 1999 Total Deaths in the United States") +
        theme(legend.position = "bottom") +
        geom_point()
    
    # plotly + keep legend
    
    plot_3 <- ggplotly(plot_3) %>%
      layout(showlegend=T)
    
      })
    
    output$pills <- renderImage({

# Return a list containing the filename. This specifies size and alt text as
# well.
      
      list(src = "pills.jpg",
           contentType = 'image/jpg',
           width = 600,
           height = 450,
           style = "display: block; margin-left: auto; margin-right: auto;")
    }, deleteFile = FALSE)
    
    # previously had the code but bc too little instant space, I had to switch
    # the code out for a png of the treatment center distribution
    
    output$treatment_centers_per_capita <- renderImage({
        
# Return a list containing the filename. This specifies size and alt text as
# well.
      
        list(src = "treatment_centers_per_capita.png",
             contentType = 'image/png',
            width = 720,
            height = 540,
             alt = "This is alternate text")
      }, deleteFile = FALSE)
    
    output$masstreat <- renderLeaflet ({
      leaflet(options = leafletOptions(dragging = TRUE,
                                     minZoom = 8,
                                     maxZoom = 9)) %>%
      addProviderTiles("CartoDB") %>%
      addCircleMarkers(data = treatment_locations_map_mas,
                       radius = 3,
                       label = ~`Program Name`)
      })
    
    # Graph deaths by age group/race using if/else
    
    output$ageandrace <-  renderPlot({
      if(input$typeoffactor == "Age"){
      ggplot(ageandracemodel, aes(year, deathsbyage, color = age_range)) +
      geom_point() +
      scale_color_viridis_d() +
      theme_classic() +
      geom_smooth(method = "lm", se = FALSE) +
      labs(title = "Cumulative Number of Opioid Deaths by Age Range",
           x = "Year", y = "Number of Opioid Deaths in America", 
           color = "Age Range") +
          theme(plot.title = element_text(size=18),
                axis.text=element_text(size=14, face = "bold"),
                axis.title=element_text(size=16,face="bold"))}
      else{
      ggplot(ageandracemodel, aes(year, deathsbyrace, color = race)) +
        geom_point() +
        scale_color_viridis_d() +
        theme_classic() +
        geom_smooth(method = "lm", se = FALSE) +
        labs(title = "Cumulative Number of Opioid Deaths by Race",
             x = "Year", y = "Number of Opioid Deaths in America", 
             color = "Race") +
          theme(plot.title = element_text(size=18),
                axis.text=element_text(size=14, face = "bold"),
                axis.title=element_text(size=16, face = "bold"))}
    })
    
    # simple linear regression deaths over time by age
    
    output$coefage <- renderDT({
      ageopioidmodel %>%
        filter(age_range == input$`Age Group`) %>%
        lm(number_of_deaths ~ year, data = .) %>%
        tidy(conf.int = TRUE) %>%
        select(term, estimate, conf.low, conf.high) %>%
        rename(Term = term) %>%
        rename(Coefficient = estimate) %>%
        rename(`Lower End` = conf.low) %>%
        rename(`Upper End` = conf.high)
    })
    
    # simple linear regression deaths over time by race
    
    output$coefrace <- renderDT({
      raceopioidmodel %>%
        filter(race == input$Race) %>%
        lm(opioid_deaths ~ year, data = .) %>%
        tidy(conf.int = TRUE) %>%
        select(term, estimate, conf.low, conf.high) %>%
        rename(Term = term) %>%
        rename(Coefficient = estimate) %>%
        rename(`Lower End` = conf.low) %>%
        rename(`Upper End` = conf.high)
  })}
shinyApp(ui, server)
