# Load packages
library(shiny)
library(dplyr)
library(tidyr)
library(readr)
library(shinythemes)
library(shinyWidgets)
library(plotly)
#library(tidyverse)
#library(htmlwidgets)
#library(lubridate)
#library(ggthemes)
#library(tibbletime)
#library(directlabels)

#################################
# Load all data
# should be online so things update automatically
#################################
#US data
#from https://covidtracking.com/

#for speed, we should do it such that it only gets it from the API if the data is old, otherwise it should load locally
if (file.exists('cleandata.RDS') && as.Date(file.mtime('cleandata.RDS')) ==  Sys.Date()) {
  #################################
  # load already clean data locally
  #################################
  us_data <- readRDS('cleandata.RDS')
} else {
  #################################
  # pull data from Covidtracking and process
  #################################
  
  us_data <- read_csv("http://covidtracking.com/api/states/daily.csv")
  us_clean <- us_data %>% dplyr::select(c(date,state,positive,negative,total,hospitalized,death)) %>%
    mutate(date = as.Date(as.character(date),format="%Y%m%d")) %>% 
    group_by(state) %>% arrange(date) %>%
    mutate(all_positive = cumsum(positive)) %>% 
    mutate(all_negative = cumsum(negative)) %>% 
    mutate(all_total = cumsum(total)) %>% 
    mutate(all_hospitalized = cumsum(hospitalized)) %>% 
    mutate(all_death = cumsum(death))  
    saveRDS(us_clean,'cleandata.RDS')
}

#world_cases <- readr::read_csv("https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_confirmed_global.csv")
#word_deaths <- read_csv("https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_deaths_global.csv")

#data for population size for each state/country so we can compute cases per 100K
us_popsize <- readRDS("./us_popsize.RDS")
us_clean <- merge(us_popsize, us_clean)  
#World_popsize <- 


state_var = unique(us_clean$state)

# Define UI
ui <- fluidPage(theme = shinytheme("lumen"),
                titlePanel("COVID-19"),
                sidebarLayout(
                  sidebarPanel(
                    withMathJax(),
                    #State selector coding with Cali Wash and GA as awlays selected for a defult setting, will flash an error with none selected
                    #Picker input = drop down bar
                    shinyWidgets::pickerInput("state_selector", "Select States", state_var, multiple = TRUE, 
                                              options = list(`actions-box` = TRUE),
                                              selected = c("CA","WA", "GA")),
                    #Shiny selectors below major picker input
                    shiny::selectInput("case_death", "Outcome",c("Cases" = "case", "Deaths" = "death"), selected = "Cases"),
                    shiny::selectInput("daily_tot", "Daily Count or Cumulative Total Count",c("Daily" = "daily", "Total" = "tot"), selected ="Total"),
                    
                    shiny::selectInput("absolute_scaled", "Absolute or scaled values",c("Absolute number" = "actual", "Per 100K" = "scaled")),
                    
                    # It would be nice if we could get the X Cases to auto-change to match the selector below
                    shiny::selectInput("xscale", "Set x-axis to calendar date or days since a set number of cases",c("Calendar Date" = "x_time", "Days Since X Cases" = "x_count")),
                    sliderInput(inputId = "count_limit", "Choose the number of cases at which to start graphs", min = 1, max = 500, value = 100),
                    shiny::selectInput("yscale", "Y-scale",c("linear" = "linear", "logarithmic" = "logarithmic"), selected = "logarithmic"),
                    br(), br()
                  ),
                  
                  # Output:
                  mainPanel(
                    #change to plotOutput if using static ggplot object
                    plotlyOutput(outputId = "case_death_plot", height = "300px"),
                    #change to plotOutput if using static ggplot object
                    plotlyOutput(outputId = "testing_plot", height = "300px"),
                    #change to plotOutput if using static ggplot object
                    plotlyOutput(outputId = "testing_frac_plot", height = "300px")
                  )
                )
)

# Define server function
server <- function(input, output) {
  
  #Reactive function to prepare plot data
  get_plot_data <- reactive({  
    
    #choose either cases or deaths to plot
    if (input$case_death == 'case' && input$daily_tot == 'daily' && input$absolute_scaled == 'actual')
    {
      plot_dat <- us_clean %>% mutate(outcome = positive) %>%  
                            mutate(test_outcome = total) %>%
                            mutate(test_frac_outcome = positive/(total+1)) #add 1 to prevent divide by 0
      y_labels <- c("Daily New Case Count", "Daily Number of Tests", "Daily Positive Test Proportion")
      tool_tip <- c("Date", "Cases", "Tests", "Positive Test Proportion")
    }
    if (input$case_death == 'death' && input$daily_tot == 'daily' && input$absolute_scaled == 'actual')
    {
      plot_dat <- us_clean %>% mutate(outcome = death)  %>%
                           mutate(test_outcome = total) %>%
                          mutate(test_frac_outcome = positive/(total+1))
      y_labels <- c("Daily Fatality Count", "Daily Number of Tests", "Daily Positive Test Proportion")
      tool_tip <- c("Date","Fatalities", "Tests", "Positive Test Proportion")
    }
    if (input$case_death == 'case' && input$daily_tot == 'tot' && input$absolute_scaled == 'actual')
    {
      plot_dat <- us_clean %>% mutate(outcome = all_positive) %>%  
                            mutate(test_outcome = all_total)%>%
                            mutate(test_frac_outcome = all_positive/(all_total+1))
      y_labels <- c("Cumulative Case Count", "Cumulative Test Count", "Cumulative Positive Test Proportion")
      tool_tip <- c("Date","Cases", "Tests", "Positive Test Proportion")
      
    }
    if (input$case_death == 'death' && input$daily_tot == 'tot' && input$absolute_scaled == 'actual')
    {
      plot_dat <- us_clean %>% mutate(outcome = all_death) %>% 
                            mutate(test_outcome = all_total) %>%
                            mutate(test_frac_outcome = all_positive/(all_total+1))
      y_labels <- c("Cumulative Fatality Count", "Cumulative Test Count", "Cumulative Positive Test Proportion")
      tool_tip <- c("Date","Fatalities", "Tests", "Positive Test Proportion")
    }
    
    #choose either cases or deaths to plot for 100k
    if (input$case_death == 'case' && input$daily_tot == 'daily' && input$absolute_scaled == 'scaled')
    {
      plot_dat <- us_clean %>% mutate(outcome = (positive / total_pop) * 100000) %>%  
        mutate(test_outcome = (total / total_pop) * 100000) %>%
        mutate(test_frac_outcome = ((positive/(total+1)) / total_pop) * 100000) #add 1 to prevent divide by 0
      y_labels <- c("Daily New Case Count", "Daily Number of Tests", "Daily Positive Test Proportion")
      tool_tip <- c("Date", "Cases", "Tests", "Positive Test Proportion")
    }
    if (input$case_death == 'death' && input$daily_tot == 'daily' && input$absolute_scaled == 'scaled')
    {
      plot_dat <- us_clean %>% mutate(outcome = (death / total_pop) * 100000)  %>%
        mutate(test_outcome = (total / total_pop) * 100000) %>%
        mutate(test_frac_outcome = ((positive/(total+1)) / total_pop) * 100000)
      y_labels <- c("Daily Fatality Count", "Daily Number of Tests", "Daily Positive Test Proportion")
      tool_tip <- c("Date","Fatalities", "Tests", "Positive Test Proportion")
    }
    if (input$case_death == 'case' && input$daily_tot == 'tot' && input$absolute_scaled == 'scaled')
    {
      plot_dat <- us_clean %>% mutate(outcome = (all_positive / total_pop) * 100000) %>%  
        mutate(test_outcome = (all_total / total_pop) * 100000) %>%
        mutate(test_frac_outcome = ((all_positive/(all_total+1)) / total_pop) * 100000)
      y_labels <- c("Cumulative Case Count", "Cumulative Test Count", "Cumulative Positive Test Proportion")
      tool_tip <- c("Date","Cases", "Tests", "Positive Test Proportion")
      
    }
    if (input$case_death == 'death' && input$daily_tot == 'tot' && input$absolute_scaled == 'scaled')
    {
      plot_dat <- us_clean %>% mutate(outcome = (all_death / total_pop) * 100000) %>% 
        mutate(test_outcome = (all_total / total_pop) * 100000) %>%
        mutate(test_frac_outcome = ((all_positive/(all_total+1)) / total_pop) * 100000)
      y_labels <- c("Cumulative Fatality Count", "Cumulative Test Count", "Cumulative Positive Test Proportion")
      tool_tip <- c("Date","Fatalities", "Tests", "Positive Test Proportion")
    }
    
    #adjust data to align for plotting by cases on x-axis. 
    #Takes the plot_dat object created above to then designate further functionality
    if (input$xscale == 'x_count')
    {
      #Takes plot_dat and filters All_counts by the predetermined count limit from the reactive above
      #Created the tme variable (which represents the day number of the outbreak) from the date variable
      #Groups data by state/province
      #Will plot the number of days since the selected count_limit or the date
      plot_dat <- plot_dat %>% mutate(count_limit = input$count_limit) %>%
        filter(all_positive >= count_limit) %>%  
        mutate(Time = as.numeric(date)) %>%
        group_by(state) %>% 
        mutate(Time = Time - min(Time))
      tool_tip[1] <- "Days Since X Cases"
      list(plot_dat, y_labels, tool_tip)
    }
    else
    {
      plot_dat <- plot_dat %>% mutate(Time = date)
      list(plot_dat, y_labels, tool_tip)
    } 
  }) #end reactive function that produces the right plot_dat data needed
  
  
  #make the plot for cases/deaths
  output$case_death_plot <- renderPlotly({
    tool_tip <- get_plot_data()[[3]]
    scaleparam <- "fixed"
    p1 <- get_plot_data()[[1]] %>% 
      #Filter data for cases >0 and selected states
      filter(outcome > 0) %>% 
      filter(state %in% input$state_selector) %>% 
      #Begin plot
      ggplot(aes(x=Time, y = outcome, color = state))+
      geom_line()+
      geom_point(aes(text = paste(paste0("State: ", state), paste0(tool_tip[1], ": ", Time),paste0(tool_tip[2],": ", outcome),sep ="\n")))+
      theme_light() + 
      ylab(get_plot_data()[[2]][1])
    #Flip to logscale if selected
    if(input$yscale == "logarithmic") {
      p1 <- p1 + scale_y_log10() 
    }
    ggplotly(p1, tooltip = "text")
  }) #end function making case/deaths plot
  
  #make the testing plots 
  output$testing_plot <- renderPlotly({
    scaleparam <- "fixed"
    tool_tip <- get_plot_data()[[3]]
    p2 <- get_plot_data()[[1]] %>% 
      #Filter data for cases >0 and selected states
      filter(test_outcome > 0) %>% 
      filter(state %in% input$state_selector) %>% 
      #Begin plot
      ggplot(aes(x=Time, y = test_outcome, color = state))+
      geom_line()+
      geom_point(aes(text = paste(paste0("State: ", state), paste0(tool_tip[1], ": ", Time),paste0(tool_tip[3],": ", test_outcome),sep ="\n")))+
      theme_light()+
      ylab(get_plot_data()[[2]][2])
    #Flip to logscale if selected
    if(input$yscale == "logarithmic") {
      p2 <- p2 + scale_y_log10() 
    }
    ggplotly(p2, tooltip = "text")
  }) #end function making testing plot
  
  #make the fraction positive testing plots 
  output$testing_frac_plot <- renderPlotly({
    scaleparam <- "fixed"
    tool_tip <- get_plot_data()[[3]]
    p3 <- get_plot_data()[[1]] %>% 
      #Filter data for cases >0 and selected states
      filter(test_frac_outcome > 0) %>% 
      filter(state %in% input$state_selector) %>% 
      #Begin plot
      ggplot(aes(x=Time, y = test_frac_outcome, color = state))+
      geom_line()+
      geom_point(aes(text = paste(paste0("State: ", state), paste0(tool_tip[1], ": ", Time),paste0(tool_tip[4],": ", round(test_frac_outcome, digits =3)),sep ="\n")))+
      theme_light() +
      ylab(get_plot_data()[[2]][3])
      ggplotly(p3, tooltip = "text")
  }) #end function making testing plot
  
} #end server function

# Create Shiny object
shinyApp(ui = ui, server = server)
