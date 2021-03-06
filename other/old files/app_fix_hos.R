# Load packages
library(dplyr)
library(tidyr)
library(readr)
library(shiny)
library(shinyWidgets)
library(ggplot2)
library(plotly)
#library(scales)
#library(shinythemes)
#library(htmlwidgets)
#library(ggthemes)
#library(tibbletime)
#library(directlabels)


#################################
# Load all data
# should be online so things update automatically
#for speed, we only get data from the online source if the data is old, otherwise we load locally
#################################

#################################
#US data from https://covidtracking.com/
if (file.exists('us_cleandata.rds') && as.Date(file.mtime('us_cleandata.rds')) ==  Sys.Date()) {
    #################################
    # load already clean data locally
    #################################
    us_clean <- readRDS('us_cleandata.rds')
} else {
    #################################
    # pull data from Covidtracking and process
    #################################
    us_data <- read_csv("https://covidtracking.com/api/states/daily.csv")
    #data for population size for each state/country so we can compute cases per 100K
    us_popsize <- readRDS("us_popsize.rds")
    us_clean <- us_data %>% dplyr::select(c(date,state,positive,negative,total,hospitalized,death)) %>%
        mutate(date = as.Date(as.character(date),format="%Y%m%d")) %>% 
        group_by(state) %>% arrange(date) %>%
        mutate(Daily_Test_Positive = c(0,diff(positive))) %>% 
        mutate(Daily_Test_Negative = c(0,diff(negative))) %>% 
        mutate(Daily_Test_All = c(0,diff(total))) %>% 
        mutate(Daily_Hospitalized = c(0,diff(hospitalized))) %>% 
        mutate(Daily_Deaths = c(0,diff(death))) %>%
        merge(us_popsize) %>%
        rename(Date = date, Location = state, Population_Size = total_pop, Total_Deaths = death, 
              Total_Cases = positive, Total_Hospitalized = hospitalized, 
              Total_Test_Negative = negative, Total_Test_Positive = positive, Total_Test_All = total) %>%
        mutate(Daily_Cases = Daily_Test_Positive, Total_Cases = Total_Test_Positive)
    #Change NA hospitalizations to zero

    
    saveRDS(us_clean,'us_cleandata.rds')
}

#################################
#Pull and clean world data
if (file.exists('world_cleandata.rds') && as.Date(file.mtime('world_cleandata.rds')) ==  Sys.Date()) {
    #################################
    # load already clean data locally
    #################################
    world_clean <- readRDS('world_cleandata.rds')
} else {
    #################################
    # pull world data from JHU github and process
    #################################
    world_cases <- readr::read_csv("https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_confirmed_global.csv")
    world_deaths <- read_csv("https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_deaths_global.csv")
    world_popsize <-readRDS("./world_popsize.rds") 
    # clean the data for plotting
    world_cases <- world_cases %>% dplyr::select(c(-`Province/State`, -Lat, -Long)) %>%
        rename(country= `Country/Region`)
    world_cases <- aggregate(. ~ country, world_cases, FUN = sum)
    world_deaths <- world_deaths %>% dplyr::select(c(-`Province/State`, -Lat, -Long)) %>%
        rename(country= `Country/Region`)
    world_deaths <- aggregate(. ~ country, world_deaths, FUN = sum)
    #Melt case and death data
    world_cases <- merge(world_popsize, world_cases)
    melt_cases <- gather(world_cases, date, cases, -country, -country_pop)
    world_deaths <- merge(world_deaths, world_popsize)
    melt_deaths <- gather(world_deaths, date, deaths, -country, -country_pop)
    all_merge <- merge(melt_deaths, melt_cases)
    world_clean <- all_merge %>% mutate(date = as.Date(as.character(date),format="%m/%d/%y")) %>%
        group_by(country) %>% arrange(date) %>%
        mutate(Daily_Cases = c(0,diff(cases))) %>%
        mutate(Daily_Deaths = c(0,diff(deaths))) %>% 
        ungroup() %>%
        rename(Date = date, Total_Deaths = deaths, Total_Cases = cases, Location = country, Population_Size = country_pop) %>% 
        data.frame()
    
    saveRDS(world_clean,"world_cleandata.rds")
}

state_var = unique(us_clean$Location)
country_var = unique(world_clean$Location)

#################################
# Define UI
#################################
ui <- fluidPage(
  tags$head(includeHTML(("google-analytics.html"))), #this is for Google analytics tracking.
  includeCSS("appstyle.css"),
    #main tabs
    navbarPage( title = "YACT - Yet Another COVID-19 Tracker", id = 'alltabs', selected = "us", header = "",
        tabPanel(  title = "US", value = "us",
                  fluidRow( uiOutput('us_ui'), class = "mainmenurow" )
                ), #close US tab
        tabPanel( title = "World", value = "world",
                  fluidRow( uiOutput('world_ui'), class = "mainmenurow" )
                ), #close world tab
        tabPanel( title = "About", value = "about",
                  fluidRow( uiOutput('about_ui'), class = "mainmenurow" )
                ) #close about tab
          ) #close NavBarPage
) #end fluidpage and UI part of shiny app
#end UI of shiny app
###########################################


###########################################
# Define server functions
###########################################
server <- function(input, output, session) {

  
  ###########################################
  # function that takes UI settings and produces data for each plot
  ###########################################
  set_outcome <- function(plot_dat,case_death,daily_tot,absolute_scaled,xscale,count_limit,selected_tab,location_selector)
  {
    
    out_type = paste(daily_tot,case_death,sep='_') #make string from UI inputs that correspond with variable names
    
    plot_dat <- plot_dat %>%   filter(Location %in% location_selector) %>%      #Only process data for locations that are  selected
                               mutate(outcome = get(out_type)) #pick output based on variable name created from UI
                               
    
    # # do testing data for US 
    if (selected_tab == "us")  
    {
      test_out_type = paste(daily_tot,'Test_All',sep='_')
      test_pos_type = paste(daily_tot,'Test_Positive',sep='_')
      plot_dat <- plot_dat %>% mutate(test_outcome = get(test_out_type)) 
      plot_dat <- plot_dat %>% mutate(test_frac_outcome = get(test_pos_type)/get(test_out_type))
    }
    
    #if we want scaling by 100K, do extra scaling 
    if (absolute_scaled == 'scaled')
    {
      plot_dat <- plot_dat %>% mutate(outcome = outcome / Population_Size * 100000) 
      if (selected_tab == "us" )  
      {
        plot_dat <- plot_dat %>%  mutate(test_outcome = test_outcome / Population_Size * 100000)
      }
    }
    #set labels and tool tips based on input - entries 2 and 3 are ignored for world plot
    y_labels <- c("Cases", "Tests", "Positive Test Proportion")
    y_labels[1] <- case_death #fill that automatically with either Case/Hosp/Death
    y_labels <- paste(daily_tot, y_labels, sep = " ")
    
    tool_tip <- c("Date", "Cases", "Tests", "Positive Test Proportion")
    tool_tip[2] <- case_death #fill that automatically with either Case/Hosp/Death
    
    #adjust data to align for plotting by cases on x-axis. 
    if (xscale == 'x_count')
    {
      #Takes plot_dat and filters counts by the predetermined count limit from the reactive above
      #Created the time variable (which represents the day number of the outbreak) from the date variable
      #Will plot the number of days since the selected count_limit or the date
      
      out_type2 = paste0("Total_",case_death) #make string from UI inputs that correspond to total and selected outcome
      plot_dat <- plot_dat %>% 
        filter(get(out_type2) >= count_limit) %>%  
        mutate(Time = as.numeric(Date)) %>%
        group_by(Location) %>% 
        mutate(Time = Time - min(Time))
      
    }
    else
    {
      plot_dat <- plot_dat %>% mutate(Time = Date)
    }
    #sort dates for plotting
    plot_dat <- plot_dat %>% group_by(Location) %>% arrange(Time) %>% ungroup()
    
    
    list(plot_dat, y_labels, tool_tip) #return list
  } #end function that produces output for plots
  
  ###########################################
  # function that takes data generated by above function and makes plots
  # uses plotly
  ###########################################
  make_plotly <- function(plot_list, location_selector, yscale, xscale, ylabel)
  {
    tool_tip <- plot_list[[3]]
    plot_dat <- plot_list[[1]]
    
    if (yscale == "log10") {ytrans = "log"} #plotly uses different names for linear/log scale
    if (yscale == "identity") {ytrans = "lin"} #plotly uses different names for linear/log scale
    linesize = 2
    tooltip_text = paste(paste0("Location: ", plot_dat$Location), paste0(tool_tip[1], ": ", plot_dat$Date),paste0(tool_tip[ylabel+1],": ", plot_dat$outcome),sep ="\n") 
    pl <- plot_dat %>%
          plotly::plot_ly() %>%  
          add_trace(x = ~Time, y = ~outcome, type = 'scatter', mode = 'lines+markers', linetype = ~Location, 
                    line = list(color = ~Location, width = linesize), text = tooltip_text) %>%
          layout(  yaxis = list(title=plot_list[[2]][ylabel], type = ytrans, size = 18)) 
    return(pl)
  }
  
  
  ###########################################
  # function that takes data generated by above function and makes plots
  # uses ggplot, then converts to plotly
  ###########################################
  make_plot <- function(plot_list, location_selector, yscale, xscale, ylabel)
  {
    tool_tip <- plot_list[[3]]
    plot_dat <- plot_list[[1]]
    pl <- plot_dat %>%  
              ggplot(aes(x=Time, y = outcome, color = Location)) +
              geom_line() +
              geom_point(aes(text = paste(paste0("Location: ", Location), paste0(tool_tip[1], ": ", Date),paste0(tool_tip[2],": ", outcome),sep ="\n"))) +
              theme_light() +
              ggplot2::scale_y_continuous(trans = yscale) +
              ylab(plot_list[[2]][ylabel])
     if(xscale =="x_time"){
       pl <- pl + scale_x_date(date_labels = "%b %d")
     }
    pl <- ggplotly(pl, tooltip = "text") 
    return(pl)
  }
   
###########################################
#function that checks if world tab is selected and generates UI
###########################################
  observeEvent( input$alltabs == 'world', 
        {
          output$world_ui <- renderUI({
            
            sidebarLayout(
              sidebarPanel(
                #Country selector coding with US, Italy, and Spain as always selected for a defult setting, will flash an error with none selected
                shinyWidgets::pickerInput("country_selector", "Select countries", country_var,  multiple = TRUE, options = list(`actions-box` = TRUE), selected = c("US", "Italy", "Spain")                        ),
                shiny::selectInput( "case_death_w", "Outcome", c("Cases" = "Cases", "Deaths" = "Deaths")),
                shiny::div("Modify the plot to display cases or deaths."),
                br(),
                shiny::selectInput("daily_tot_w", "Daily or cumulative numbers", c("Daily" = "Daily", "Total" = "Total")),
                shiny::div("Modify the plot to reflect daily or cumulative statistics."),
                br(),
                shiny::selectInput("absolute_scaled_w", "Absolute or scaled values", c("Absolute Number" = "actual", "Per 100,000 persons" = "scaled") ),
                shiny::div("Modify the plot to display statistics representive of the total count or values scaled to the country population size."),
                br(),
                shiny::selectInput( "xscale_w", "Set x-axis to calendar date or days since a specified total number of cases/deaths", c("Calendar Date" = "x_time", "Days since N cases/deaths" = "x_count")),
                sliderInput( inputId = "count_limit_w","Choose the number of cases/deaths at which to start graphs", min = 1,  max = 500,  value = 10 ),
                shiny::div("Modify the plot to reflect the calender date or days since a selected value of cases input in the slider above."),
                br(),
                shiny::selectInput( "yscale_w",  "Y-scale", c("Linear" = "identity", "Logarithmic" = "log10")),
                shiny::div("Modify the plot to reflect a logarithmic or linear scale."),
                br(),
                ),
              
              mainPanel(
                plotlyOutput(outputId = "case_death_plot_world", height = "500px"),
              ) #close mainpanel
            ) #close sidebar layout
          }) #end render UI
       
        #make the plot for cases/deaths for world data
        output$case_death_plot_world <- renderPlotly({
          #make data for plotting
          plot_dat <- set_outcome(world_clean,input$case_death_w,input$daily_tot_w,input$absolute_scaled_w,input$xscale_w,input$count_limit_w,input$alltabs,input$country_selector)
          #create plot
          pl <- make_plotly(plot_dat, location_selector = input$country_selector, yscale = input$yscale_w, xscale = input$xscale_w, ylabel = 1)
        }) #end function making case/deaths plot          
    }) #end world observe event 
      
  ###########################################
  #function that checks if us tab is selected and generates UI
  ###########################################
  observeEvent( input$alltabs == 'us', 
  {
    output$us_ui <- renderUI({
      sidebarLayout(
        sidebarPanel(
          shinyWidgets::pickerInput("state_selector", "Select states", state_var, multiple = TRUE,options = list(`actions-box` = TRUE), selected = c("CA", "WA", "GA") ),
          shiny::selectInput( "case_death",   "Outcome",c("Cases" = "Cases", "Deaths" = "Deaths", "Hospitalizations" = "Hospitalized")),
          shiny::div("Modify the top plot to display cases, deaths, or hospitalizations."),
          br(),
          shiny::selectInput("daily_tot", "Daily or cumulative numbers", c("Daily" = "Daily", "Total" = "Total" )),
          shiny::div("Modify all three plots to reflect daily or cumulative statistics."),
          br(),
          shiny::selectInput( "absolute_scaled","Absolute or scaled values",c("Absolute Number" = "actual", "Per 100,000 persons" = "scaled") ),
          shiny::div("Modify all three plots to display statistics representive of the total count or values scaled to the state/territory population size."),
          br(),
          shiny::selectInput("xscale", "Set x-axis to calendar date or days since a specified total number of cases/hospitalizations/deaths", c("Calendar Date" = "x_time", "Days since N cases/hospitalizations/deaths" = "x_count")),
          sliderInput(  inputId = "count_limit", "Choose the number of cases/hospitalizations/deaths at which to start graphs", min = 1,  max = 500, value = 10 ),
          shiny::div("Modify all three plots to reflect the calender date or days since a selected value of cases input in the slider above."),
          br(),
          shiny::selectInput(  "yscale", "Y-scale", c("Linear" = "identity", "Logarithmic" = "log10")),
          shiny::div("Modify the top two plots to reflect a logarithmic or linear scale."),
          br(),

         ),         #end sidebar panel
        # Output:
        mainPanel(
          #change to plotOutput if using static ggplot object
          plotlyOutput(outputId = "case_death_plot", height = "300px"),
          #change to plotOutput if using static ggplot object
          plotlyOutput(outputId = "testing_plot", height = "300px"),
          #change to plotOutput if using static ggplot object
          plotlyOutput(outputId = "testing_frac_plot", height = "300px")
        ) #end main panel
      ) #end sidebar layout
    }) #end render UI
    
    
    #make the plot for cases/deaths for US data
    output$case_death_plot <- renderPlotly({
      #make data for plotting
      plot_dat <- set_outcome(us_clean,input$case_death,input$daily_tot,input$absolute_scaled,input$xscale,input$count_limit,input$alltabs,input$state_selector)
      #create plot
      pl <- make_plotly(plot_dat, location_selector = input$state_selector, yscale = input$yscale, xscale = input$xscale, ylabel = 1)
      #pl <- make_plot(plot_dat, location_selector = input$state_selector, yscale = input$yscale, xscale = input$xscale, ylabel = 1) 
    }) #end function making case/deaths plot
    
    #make the testing plot 
    output$testing_plot <- renderPlotly({
      #make data for plotting
      plot_dat <- set_outcome(us_clean,input$case_death,input$daily_tot,input$absolute_scaled,input$xscale,input$count_limit,input$alltabs,input$state_selector)
      #re-assign outcome
      plot_dat[[1]] <- plot_dat[[1]] %>% select(-outcome) %>% rename(outcome = test_outcome)
      #create plot
      pl <- make_plotly(plot_dat, location_selector = input$state_selector, yscale = input$yscale, xscale = input$xscale, ylabel = 2)
      #pl <- make_plot(plot_dat, location_selector = input$state_selector, yscale = input$yscale, xscale = input$xscale, ylabel = 2) 
    }) #end function making testing plot
    
    #make the fraction positive testing plot 
    output$testing_frac_plot <- renderPlotly({
      #make data for plotting
      plot_dat <- set_outcome(us_clean,input$case_death,input$daily_tot,input$absolute_scaled,input$xscale,input$count_limit,input$alltabs,input$state_selector)
      #re-assign outcome
      plot_dat[[1]] <- plot_dat[[1]] %>% select(-outcome) %>% rename(outcome = test_frac_outcome)
      #create plot
      pl <- make_plotly(plot_dat, location_selector = input$state_selector, yscale = input$yscale, xscale = input$xscale, ylabel = 3)
      #pl <- make_plot(plot_dat, location_selector = input$state_selector, yscale = input$yscale, xscale = input$xscale, ylabel = 3)
    }) #end function making testing plot
    
    
  }) #end observer listening to US tab choice

  
  ###########################################
  #function that checks if about tab is selected and generates UI
  ###########################################
  observeEvent( input$alltabs == 'about', 
  {
    output$about_ui <- renderUI({
      tagList(    
      fluidRow( #all of this is the header
            #tags$div(id = "shinyheadertitle", "YACT - Yet Another COVID-19 Tracker"),
            #the style 'shinyheadertitle' is defined in the appstyle.css file
            tags$div(
              id = "bigtext",
              "This COVID-19 tracker is brought to you by the",
              a("Center for the Ecology of Infectious Diseases",  href = "https://ceid.uga.edu", target = "_blank" ),
              "and the",
              a("College of Public Health", href = "https://publichealth.uga.edu", target = "_blank"),
              "at the",
              a("University of Georgia.", href = "https://www.uga.edu", target = "_blank"),
              "It was developed by",
              a("Robbie Richards,", href = "https://rlrichards.github.io", target =  "_blank"),
              a("William Norfolk", href = "https://github.com/williamnorfolk", target = "_blank"),
              "and ",
              a("Andreas Handel.", href = "https://www.andreashandel.com/", target = "_blank"),
              "Underlying data for the US is sourced from",
              a("The Covid Tracking Project,",  href = "https://covidtracking.com/", target = "_blank" ),
              "world data is sourced from the",
              a("Johns Hopkins University Center for Systems Science and Engineering.", href = "https://github.com/CSSEGISandData/COVID-19", target = "_blank" ),
              'Source code for this project can be found',
              a( "in this GitHub repository.", href = "https://github.com/CEIDatUGA/COVID-shiny-tracker", target = "_blank" ),
              'We welcome feedback and feature requests, please send them as a',
              a( "GitHub Issue", href = "https://github.com/CEIDatUGA/COVID-shiny-tracker/issues", target = "_blank" ),
              'or contact',
              a("Andreas Handel.", href = "https://www.andreashandel.com/", target = "_blank"),
              a( "The Center for the Ecology of Infectious Diseases", href = "https://ceid.uga.edu", target = "_blank" ),
              'has several additional projects related to COVID-19, which can be found on the',
              a( "CEID Coronavirus tracker website.", href = "http://2019-coronavirus-tracker.com/", target = "_blank" )
            ), #Close the bigtext text div
          ), #close fluidrow
          fluidRow( #all of this is the footer
              column(3,
                     a(href = "https://ceid.uga.edu", tags$img(src = "ceidlogo.png", width = "100%"), target = "_blank"),
              ),
              column(6,
                     p('All text and figures are licensed under a ',
                       a("Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License.",
                         href = "http://creativecommons.org/licenses/by-nc-sa/4.0/", target = "_blank"),
                       'Software/Code is licensed under ',
                       a("GPL-3.", href = "https://www.gnu.org/licenses/gpl-3.0.en.html" , target =  "_blank"),
                       'See source data sites for licenses governing data.',
                       a("UGA's Privacy Policy.", href = "https://eits.uga.edu/access_and_security/infosec/pols_regs/policies/privacy/" , target =  "_blank"),
                       align = "center",
                       style = "font-size:small"
                     ) #end paragraph
              ), #end middle column
              column(3,
                     a(href = "https://publichealth.uga.edu", tags$img(src = "cphlogo.png", width = "100%"), target = "_blank")
              ) #end left column
            ) #end fluidrow
      ) #end taglist
    }) #end renderUI 
    }) #end observer listening to about tab choice
        

} #end server function

# Create Shiny object
shinyApp(ui = ui, server = server)