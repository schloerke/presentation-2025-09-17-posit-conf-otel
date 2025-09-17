# -- Set up chat tool calls ---------------------------------------------------

# Create tool that grabs the weather forecast (free) for a given lat/lon
# Enhanced from: https://posit-dev.github.io/shinychat/r/articles/tool-ui.html#alternative-html-display
get_weather_forecast <- ellmer::tool(
  function(lat, lon, location_name) {
    # Get weather forecast within background process
    mirai::mirai(
      {
        otel::log_info(
          "Getting weather forecast",
          logger = otel::get_logger("weather-app")
        )
        # `{weathR}` uses `{httr2}` under the hood
        forecast_data <- weathR::point_tomorrow(lat, lon, short = FALSE)

        # Present as a nicely formatted table
        forecast_table <- gt::as_raw_html(gt::gt(forecast_data))

        list(data = forecast_data, table = forecast_table)
      },
      lat = lat,
      lon = lon
    ) |>
      promises::then(function(forecast_info) {
        ellmer::ContentToolResult(
          forecast_info$data,
          extra = list(
            display = list(
              html = forecast_info$table,
              title = paste("Weather Forecast for", location_name)
            )
          )
        )
      })
  },
  name = "get_weather_forecast",
  description = "Get the weather forecast for a location.",
  arguments = list(
    lat = ellmer::type_number("Latitude"),
    lon = ellmer::type_number("Longitude"),
    location_name = ellmer::type_string(
      "Name of the location for display to the user"
    )
  ),
  annotations = ellmer::tool_annotations(
    title = "Weather Forecast",
    icon = bsicons::bs_icon("cloud-sun")
  )
)


# -- App ----------------------------------------------------------------------

library(shiny)
mirai::daemons(1)
onStop(function() mirai::daemons(0))

ui <- bslib::page_fillable(
  shinychat::chat_mod_ui("chat", height = "100%")
  # ,
  # shiny::actionButton(
  #   "close_btn",
  #   label = "",
  #   class = "btn-close",
  #   style = "position: fixed; top: 6px; right: 6px;"
  # )
)
server <- function(input, output, session) {
  # Set up client within `server` to not _share_ the client for all sessions
  client <- ellmer::chat_anthropic("Be terse.")
  client$register_tool(get_weather_forecast)

  withr::with_options(
    list(shiny.otel.bind = "none"),
    {
      chat_server <- shinychat::chat_mod_server("chat", client, session)

      # shiny::observeEvent(input$close_btn, {
      #   shiny::stopApp()
      # })

      # # Set the UI
      # observeEvent(
      #   once = TRUE,
      #   TRUE, # Allow once reactivity is ready
      #   {
      #     # chat_server$update_user_input("What is the weather in Atlanta, GA?")

      #     later::later(
      #       function() {
      #         # withRe
      #         chat_server$update_user_input(
      #           "Pick a random city in the US and get its weather forecast.",
      #           submit = TRUE
      #         )
      #       },
      #       2
      #     )
      #   }
      # )

      observeEvent(
        {
          chat_server$last_turn()
        },
        {
          req(chat_server$last_turn())
          turn_txt <- ellmer::contents_text(chat_server$last_turn())
          # message(turn_txt)
          req(nchar(turn_txt) > 75)
          # later::later(
          #   function() {
          #     shiny::stopApp()
          #   },
          #   4
          # )
          later::later(
            function() {
              session$close()
            },
            3
          )
        }
      )
    }
  )
}


shinyApp(ui, server, options = list(port = 8080, launch.browser = FALSE))
