# ETAPA DE PROCESS

if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
if (!requireNamespace("lubridate", quietly = TRUE)) install.packages("lubridate")
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2")
library(dplyr)
library(lubridate)
library(ggplot2)

#csv_files <- list.files(pattern = "(202[0-4]([0-1][0-9])?-divvy-(tripdata|publictripdata)(-Q[1-4])?).*\\.csv$")
csv_files <- list.files(pattern = "(202[0-4]([0-1][0-9])-divvy-(tripdata|publictripdata)).*\\.csv$")
print(csv_files)

read_and_standardize <- function(file) {
  df <- read.csv(file)
  df$start_station_id <- as.character(df$start_station_id)
  df$end_station_id <- as.character(df$end_station_id)
  df$ride_id <- as.character(df$ride_id)
  return(df)
}

combined_data <- bind_rows(lapply(csv_files, read_and_standardize))

str(combined_data)
summary(combined_data)
sum(duplicated(combined_data$ride_id))
colSums(is.na(combined_data))
head(combined_data$started_at, 20)  # Muestra valores
# Verifica formatos problemáticos
invalid_dates <- combined_data$started_at[is.na(parse_date_time(combined_data$started_at, orders = c("ymd HMS", "ymd")))]
print(invalid_dates)  # Muestra valores no parseados

# Inspect dates before parsing (for debugging, outside the pipeline)
cat("Datos iniciales de started_at:\n")
print(head(combined_data$started_at, 20))

# Identify invalid dates (for documentation/debugging)
invalid_started <- combined_data$started_at[is.na(parse_date_time(combined_data$started_at, orders = c("ymd HMS", "ymd")))]
invalid_ended <- combined_data$ended_at[is.na(parse_date_time(combined_data$ended_at, orders = c("ymd HMS", "ymd")))]
cat("Invalid started_at values:\n")
print(invalid_started)
cat("Invalid ended_at values:\n")
print(invalid_ended)

# Now the cleaning pipeline (no prints inside)
cleaned_data <- combined_data %>%
  mutate(
    started_at = parse_date_time(started_at, orders = c("ymd HMS", "ymd")),
    ended_at = parse_date_time(ended_at, orders = c("ymd HMS", "ymd"))
  ) %>%
  # Remove rows with NA dates after parsing
  filter(!is.na(started_at) & !is.na(ended_at)) %>%
  # Calculate duration in minutes
  mutate(duration_min = as.numeric(difftime(ended_at, started_at, units = "mins"))) %>%
  # Filter durations: >=1 min and <=1440 min (24 hours)
  filter(duration_min >= 1 & duration_min <= 1440) %>%
  # Add other derived columns (month, day_of_week, hour_start)
  mutate(
    month = month(started_at, label = TRUE),
    day_of_week = wday(started_at, label = TRUE),
    hour_start = hour(started_at)
  ) %>%
  # Handle NA stations and rideable_type (impute to "Unknown")
  mutate(
    start_station_name = ifelse(is.na(start_station_name), "Unknown", start_station_name),
    end_station_name = ifelse(is.na(end_station_name), "Unknown", end_station_name),
    rideable_type = ifelse(is.na(rideable_type), "Unknown", rideable_type)
  ) %>%
  # Remove lat/lng columns
  select(-c(start_lat, start_lng, end_lat, end_lng))

# Inspect after cleaning (for debugging)
cat("Datos después de parseo y filtro:\n")
print(head(cleaned_data$started_at, 20))
summary(cleaned_data$duration_min)  # Check durations

# Export the cleaned data
write.csv(cleaned_data, "cleaned_divvy_data.csv", row.names = FALSE)

# ETAPA DE ANALYZE

# Load required packages
library(tidyverse)
library(lubridate)
library(scales)

# Read and convert date columns
cleaned_data <- read.csv("cleaned_divvy_data.csv", stringsAsFactors = FALSE)
cleaned_data$started_at <- ymd_hms(cleaned_data$started_at)
cleaned_data$ended_at <- ymd_hms(cleaned_data$ended_at)

# Filter out invalid datetime entries
cleaned_data <- cleaned_data %>% filter(!is.na(started_at) & !is.na(ended_at))

# Derive hour_start
cleaned_data$hour_start <- hour(cleaned_data$started_at)

# Summary statistics by member_casual (total rides, avg, median, max duration)
summary_stats <- cleaned_data %>%
  group_by(member_casual) %>%
  summarise(
    total_rides = n(),
    avg_duration_min = mean(duration_min),
    median_duration_min = median(duration_min),
    max_duration_min = max(duration_min)
  )
print(summary_stats)

# Rides by day of week and member_casual
rides_by_day <- cleaned_data %>%
  group_by(member_casual, day_of_week) %>%
  summarise(total_rides = n(), .groups = "drop") %>%
  arrange(member_casual, day_of_week)
print(rides_by_day)

# Rides by hour and member_casual
rides_by_hour <- cleaned_data %>%
  group_by(member_casual, hour_start) %>%
  summarise(total_rides = n(), .groups = "drop") %>%
  arrange(member_casual, hour_start)
print(rides_by_hour)

# Rides by rideable_type and member_casual (e.g., classic, electric)
rides_by_type <- cleaned_data %>%
  group_by(member_casual, rideable_type) %>%
  summarise(total_rides = n(), avg_duration_min = mean(duration_min), .groups = "drop")
print(rides_by_type)

bike_type_prefs <- rides_by_type %>%
  group_by(member_casual) %>%
  mutate(percentage = total_rides / sum(total_rides) * 100) %>%
  ungroup() %>% 
  # Customize bike type names for the legend
  mutate(rideable_type = recode(rideable_type,
                                "classic_bike" = "Classic Bike",
                                "docked_bike" = "Docked Bike",
                                "electric_bike" = "Electric Bike",
                                "electric_scooter" = "Electric Scooter"))
print (bike_type_prefs)

# Trends by month and year
cleaned_data$month <- month(cleaned_data$started_at, label = TRUE)
trends_by_month <- cleaned_data %>%
  group_by(year = year(started_at), month, member_casual) %>%
  summarise(total_rides = n(), avg_duration_min = mean(duration_min), .groups = "drop") %>%
  arrange(year, month)
print(trends_by_month)

# Visualizations
# Bar chart: Rides by day of week
gp <- ggplot(rides_by_day, aes(x = day_of_week, y = total_rides, fill = member_casual)) +
  geom_bar(stat = "identity", position = "dodge") +
  labs(title = "Total Rides by Day of Week (2023-2024)", 
       x = "Day of Week", 
       y = "Total Rides", 
       fill = "Member Type",
       caption = "Data source: Divvy Trip Data (2023-2024)") +
  scale_y_continuous(labels = scales::comma) +  # Readable large numbers
  scale_x_discrete() +  # Use discrete scale for categorical days
  theme_minimal()
ggsave("rides_by_day.png", plot = gp, width = 10, height = 6, units = "in")
print(gp)

# Boxplot: Duration by member_casual, faceted by day of week
b <- ggplot(cleaned_data, aes(x = member_casual, y = duration_min, fill = member_casual)) +
  geom_boxplot(outlier.shape = 1, outlier.size = 1, outlier.alpha = 0.3) +  # Control outliers
  facet_wrap(~ day_of_week, scales = "free_y", ncol = 4) +  # 4 columns for better layout
  labs(title = "Ride Duration Distribution by Member Type and Day (2023-2024)",
       x = "Member Type",
       y = "Duration (minutes)",
       fill = "Member Type",
       caption = "Note: Durations >120 minutes are squished for clarity; see raw data for full range.Data source: Divvy Trip Data (2023-2024)") +
  scale_y_continuous(limits = c(0, 120), oob = scales::squish) +  # Cap y-axis at 120 min, squash outliers
  theme_minimal() +
  theme(legend.position = "top",  # Move legend to avoid clutter
        axis.text.x = element_text(angle = 45, hjust = 1))  # Rotate x-axis labels for readability
# Save the plot
ggsave("duration_boxplot.png", plot = b, width = 12, height = 8, units = "in", dpi = 300)

# Display the plot
print(b)

# Line chart: Trends by month
l <- ggplot(trends_by_month, aes(x = month, y = total_rides, color = member_casual, group = member_casual)) +
  geom_line() +
  facet_wrap(~ year, scales = "free_y") +
  labs(title = "Rides Trends by Month (2023-2024)",
       x = "Month",
       y = "Total Rides",
       color = "Member Type",
       caption = "Data source: Divvy Trip Data (2023-2024)") +
  scale_y_continuous(labels = scales::comma) +  # Readable large numbers
  theme_minimal()

# Save the plot separately
ggsave("rides_by_month.png", plot = l, width = 12, height = 6, units = "in", dpi = 300)
# Display the plot
print(l)

# Line chart: Rides by hour
h <- ggplot(rides_by_hour, aes(x = hour_start, y = total_rides, color = member_casual, group = member_casual)) +
  geom_line() +
  labs(title = "Hourly Ride Patterns (2023-2024)",
       x = "Hour of Day (0-23)",
       y = "Total Rides",
       color = "Member Type",
       caption = "Data source: Divvy Trip Data (2023-2024)") +
  scale_y_continuous(labels = scales::comma) +  # Readable large numbers
  scale_x_continuous(breaks = seq(0, 23, by = 2)) +  # Show every 2 hours
  theme_minimal()
ggsave("rides_by_hour.png", plot = h, width = 12, height = 6, units = "in", dpi = 300)
print(h)

# Pie charts for bike type preferences, one per member_casual group
p <- ggplot(bike_type_prefs, aes(x = "", y = percentage, fill = rideable_type)) +
  geom_bar(stat = "identity", width = 0.45) +  # Width for side-by-side pies
  coord_polar("y", start = 0) +  # Convert to pie chart
  facet_wrap(~ member_casual, ncol = 2) +  # Separate pies for members and casual riders
  labs(title = "Bike Type Preferences by Member Type (2023-2024)",
       x = NULL,
       y = NULL,
       fill = "Bike Type",
       caption = "Data source: Divvy Trip Data (2023-2024)") +
  scale_fill_manual(values = c(
    "Classic Bike" = "#FF6347",  # Coral for casual alignment
    "Docked Bike" = "#FA8072",   # Light coral shade
    "Electric Bike" = "#00CED1", # Dark turquoise for member alignment
    "Unknown" = "#20B2AA"       # Light turquoise shade
  )) +
  theme_minimal() +
  theme(
    axis.text = element_blank(),  # Remove axis text for cleaner pies
    axis.ticks = element_blank(),  # Remove axis ticks
    panel.grid = element_blank(),  # Remove grid lines
    legend.position = "top",  # Move legend to top
    strip.text = element_text(size = 12, face = "bold"),  # Bold facet labels
    plot.title = element_text(hjust = 0.5, size = 14, face = "bold")  # Center and style title
  ) +
  # Add percentage labels to pie slices
  geom_text(aes(label = paste0(round(percentage, 1), "%")), 
            position = position_stack(vjust = 0.5), size = 3)
ggsave("bike_type_preferences_pie.png", plot = p, width = 10, height = 6, units = "in", dpi = 300)
print(p)