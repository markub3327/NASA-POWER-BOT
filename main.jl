include("./downloader.jl")
include("./utils.jl")
include("./menu.jl")

using Base.Threads
using Dates
using DataFrames
using CSV
using YAML
using ProgressMeter

# Constants
const MONTH_PERIOD = 12
const HOUR_PERIOD = 24

function main()
    fill_value_regional, fill_value_point_daily, fill_value_point_hourly  = nothing, nothing, nothing
    parsed_args = Menu.main_menu()
    locations = YAML.load_file("config/locations.yml")

    # Prune the locations list
    for (location_name_A, point_A) in locations["target_locations"]
        for (location_name_B, point_B) in locations["target_locations"]
            if location_name_A != location_name_B
                region_A = Utils.get_area(point_A["location"], parsed_args["width"], parsed_args["height"])
                region_B = Utils.get_area(point_B["location"], parsed_args["width"], parsed_args["height"])
                iou = Utils.intersection_over_union(region_A, region_B)

                # Choose one of two locations to keep by it's power or area if defined.
                # The last option is random selection.
                if iou > 0.1
                    println("Point A: $(location_name_A)")
                    println("Point B: $(location_name_B)")
                    println("IoU: $(iou)")
                    println()

                    if (haskey(point_A, "permanent") && point_A["permanent"] == true)
                        if (haskey(point_B, "permanent") == false || point_B["permanent"] == false)
                            delete!(locations["target_locations"], location_name_B)
                        end
                    elseif (haskey(point_B, "permanent") && point_B["permanent"] == true)
                        delete!(locations["target_locations"], location_name_A)
                    else
                        if (haskey(point_A, "power") && haskey(point_B, "power"))
                            if point_A["power"] > point_B["power"]
                                delete!(locations["target_locations"], location_name_B)
                            else
                                delete!(locations["target_locations"], location_name_A)
                            end
                        elseif (haskey(point_A, "area") && haskey(point_B, "area"))
                            if point_A["area"] > point_B["area"]
                                delete!(locations["target_locations"], location_name_B)
                            else
                                delete!(locations["target_locations"], location_name_A)
                            end
                        else
                            if rand() > 0.5
                                delete!(locations["target_locations"], location_name_B)
                            else
                                delete!(locations["target_locations"], location_name_A)
                            end
                        end
                    end
                end
           end
        end 
    end

    # Save pruned version of the locations list
    YAML.write_file("config/locations_pruned.yml", locations)

    # Init progress bar
    progress_bar = Progress(((parsed_args["end"] - parsed_args["start"] + 1) * length(locations["target_locations"])), 1, "Downloading:")

    # Temporal dataset per thread
    df_regional_daily = [ DataFrame(
        DateTime = Date[],
        MonthSin = Float32[],
        DaySin = Float32[],
        MonthCos = Float32[],
        DayCos = Float32[],
        Name = String[],
        Latitude = Float32[],
        Longitude = Float32[]
    ) for _ in 1:nthreads()]
    for i in 1:nthreads()
        for j::Int in 1:parsed_args["width"] * 2 * parsed_args["height"] * 2
            df_regional_daily[i][!, "Irradiance$(j)"] = Float32[]
            df_regional_daily[i][!, "Temp$(j)"] = Float32[]
            df_regional_daily[i][!, "TempMin$(j)"] = Float32[]
            df_regional_daily[i][!, "TempMax$(j)"] = Float32[]
            df_regional_daily[i][!, "Humidity$(j)"] = Float32[]
            df_regional_daily[i][!, "WindSpeed$(j)"] = Float32[]
            df_regional_daily[i][!, "WindSpeedMin$(j)"] = Float32[]
            df_regional_daily[i][!, "WindSpeedMax$(j)"] = Float32[]
            df_regional_daily[i][!, "WindDirection$(j)"] = Float32[]
            df_regional_daily[i][!, "WindX$(j)"] = Float32[]
            df_regional_daily[i][!, "WindY$(j)"] = Float32[]
            df_regional_daily[i][!, "WindXMin$(j)"] = Float32[]
            df_regional_daily[i][!, "WindYMin$(j)"] = Float32[]
            df_regional_daily[i][!, "WindXMax$(j)"] = Float32[]
            df_regional_daily[i][!, "WindYMax$(j)"] = Float32[]
            df_regional_daily[i][!, "Pressure$(j)"] = Float32[]
        end
    end
    df_point_daily = [ DataFrame(
        DateTime = Date[],
        MonthSin = Float32[],
        DaySin = Float32[],
        MonthCos = Float32[],
        DayCos = Float32[],
        Name = String[],
        Latitude = Float32[],
        Longitude = Float32[], 
        Irradiance = Float32[]
    ) for _ in 1:nthreads()]
    df_point_hourly = [ DataFrame(
        DateTime = DateTime[],
        MonthSin = Float32[],
        DaySin = Float32[],
        HourSin = Float32[],
        MonthCos = Float32[],
        DayCos = Float32[],
        HourCos = Float32[],
        Name = String[],
        Latitude = Float32[],
        Longitude = Float32[],
        Irradiance = Float32[]
    ) for _ in 1:nthreads()]

    # Information about the downloaded dataset
    println("\u001b[33;1m----------------------------------------------------------\u001b[0m")
    println("\u001b[34;1mNASA \u001b[31;1mPower \u001b[32;1mBot\u001b[0m ⛅ 🌞 ⚡ 🛰️")
    println("Years range: $(parsed_args["start"]) - $(parsed_args["end"])")
    println("Locations:")
    for loc in keys(locations["target_locations"])
        println("          * $(loc)")
    end
    println("\u001b[33;1m----------------------------------------------------------\u001b[0m\n")

    # Downloading data
    @threads :dynamic for year in parsed_args["start"]:parsed_args["end"]
        DAY_PERIOD = Dates.daysinyear(year)

        # Region - daily
        for (location_name, point) in locations["target_locations"]
            data_regional = NASAPowerDownloader.download_regional(year, Utils.get_area(point["location"], parsed_args["width"], parsed_args["height"]), "daily", parsed_args["timeout"])
            long_name = data_regional["parameters"]["ALLSKY_SFC_SW_DWN"]["longname"]
            units = data_regional["parameters"]["ALLSKY_SFC_SW_DWN"]["units"]
            fill_value_regional = data_regional["header"]["fill_value"]

            X = Dict{String, Array{Float32}}()     # temporary
            features = data_regional["features"]
            for f in keys(features)
                irradiance = features[f]["properties"]["parameter"]["ALLSKY_SFC_SW_DWN"]
                temp = features[f]["properties"]["parameter"]["T2M"]
                temp_min = features[f]["properties"]["parameter"]["T2M_MIN"]
                temp_max = features[f]["properties"]["parameter"]["T2M_MAX"]
                humidity = features[f]["properties"]["parameter"]["RH2M"]
                wind_speed = features[f]["properties"]["parameter"]["WS10M"]
                wind_speed_min = features[f]["properties"]["parameter"]["WS10M_MIN"]
                wind_speed_max = features[f]["properties"]["parameter"]["WS10M_MAX"]
                wind_direction = features[f]["properties"]["parameter"]["WD10M"]
                pressure = features[f]["properties"]["parameter"]["PS"]
                for (i, t, t_min, t_max, h, ws, ws_min, ws_max, wd, p) in zip(irradiance, temp, temp_min, temp_max, humidity, wind_speed, wind_speed_min, wind_speed_max, wind_direction, pressure)
                    time = i[1]
                    if haskey(X, time)
                        push!(X[time], i[2])        # copying
                        push!(X[time], t[2])        # copying
                        push!(X[time], t_min[2])        # copying
                        push!(X[time], t_max[2])        # copying
                        push!(X[time], h[2])        # copying
                        push!(X[time], ws[2])       # copying
                        push!(X[time], ws_min[2])   # copying
                        push!(X[time], ws_max[2])   # copying
                        push!(X[time], wd[2])       # copying
                        push!(X[time], ws[2]*cosd(wd[2]))       # copying
                        push!(X[time], ws[2]*sind(wd[2]))       # copying
                        push!(X[time], ws_min[2]*cosd(wd[2]))   # copying
                        push!(X[time], ws_min[2]*sind(wd[2]))   # copying
                        push!(X[time], ws_max[2]*cosd(wd[2]))   # copying
                        push!(X[time], ws_max[2]*sind(wd[2]))   # copying

                        push!(X[time], p[2])        # copying
                    else
                        X[time] = [
                            i[2], 
                            t[2],
                            t_min[2],
                            t_max[2],
                            h[2], 
                            ws[2],
                            ws_min[2],  
                            ws_max[2],  
                            wd[2],
                            ws[2]*cosd(wd[2]),
                            ws[2]*sind(wd[2]),
                            ws_min[2]*cosd(wd[2]),
                            ws_min[2]*sind(wd[2]),
                            ws_max[2]*cosd(wd[2]),
                            ws_max[2]*sind(wd[2]),
                            p[2]
                        ]            # creating
                    end
                end
            end
            #println(X)

            for (t, value) in X
                t = Date(t, "yyyymmdd")
                push!(df_regional_daily[threadid()], [
                    t,
                    sinpi(month(t) / MONTH_PERIOD * 2),
                    sinpi(dayofyear(t) / DAY_PERIOD * 2),
                    cospi(month(t) / MONTH_PERIOD * 2),
                    cospi(dayofyear(t) / DAY_PERIOD * 2),
                    location_name,
                    point["location"][1], 
                    point["location"][2],
                    value...
                ])
            end

            # Point - daily
            data_point_daily = NASAPowerDownloader.download_point(year, Utils.Point(point["location"][1], point["location"][2]), "daily", parsed_args["timeout"])
            long_name = data_point_daily["parameters"]["ALLSKY_SFC_SW_DWN"]["longname"]
            units = data_point_daily["parameters"]["ALLSKY_SFC_SW_DWN"]["units"]
            fill_value_point_daily = data_point_daily["header"]["fill_value"]
            irradiance = data_point_daily["properties"]["parameter"]["ALLSKY_SFC_SW_DWN"]
            for (t, value) in irradiance
                t = Date(t, "yyyymmdd")
                push!(df_point_daily[threadid()], [
                    t,
                    sinpi(month(t) / MONTH_PERIOD * 2),
                    sinpi(dayofyear(t) / DAY_PERIOD * 2),
                    cospi(month(t) / MONTH_PERIOD * 2),
                    cospi(dayofyear(t) / DAY_PERIOD * 2),
                    location_name,
                    point["location"][1],
                    point["location"][2],
                    value
                ])
            end

            # Point - hourly
            if year >= 2001
                data_point_hourly = NASAPowerDownloader.download_point(year, Utils.Point(point["location"][1], point["location"][2]), "hourly", parsed_args["timeout"])
                long_name = data_point_hourly["parameters"]["ALLSKY_SFC_SW_DWN"]["longname"]
                units = data_point_hourly["parameters"]["ALLSKY_SFC_SW_DWN"]["units"]
                fill_value_point_hourly = data_point_hourly["header"]["fill_value"]
                irradiance = data_point_hourly["properties"]["parameter"]["ALLSKY_SFC_SW_DWN"]
                for (t, value) in irradiance
                    t = DateTime(t, "yyyymmddHH")
                    push!(df_point_hourly[threadid()], [
                        t,
                        sinpi(month(t) / MONTH_PERIOD * 2),
                        sinpi(dayofyear(t) / DAY_PERIOD * 2),
                        sinpi(hour(t) / HOUR_PERIOD * 2),
                        cospi(month(t) / MONTH_PERIOD * 2),
                        cospi(dayofyear(t) / DAY_PERIOD * 2),
                        cospi(hour(t) / HOUR_PERIOD * 2),
                        location_name,
                        point["location"][1],
                        point["location"][2],
                        value
                    ])
                end
            end

            next!(progress_bar)
        end
    end

    # Combine dataframes
    X_all_daily = vcat(df_regional_daily...)
    y_all_daily = vcat(df_point_daily...)
    y_all_hourly = vcat(df_point_hourly...)

    # remove bad data
    if !isnothing(fill_value_regional)
        for j::Int in 1:parsed_args["width"] * 2 * parsed_args["height"] * 2
            X_all_daily = filter("Irradiance$(j)" => v -> v != fill_value_regional, X_all_daily)
        end
    end
    if !isnothing(fill_value_point_daily)
        y_all_daily = filter(:Irradiance => v -> v != fill_value_point_daily, y_all_daily)
    end
    if !isnothing(fill_value_point_hourly)
        y_all_hourly = filter(:Irradiance => v -> v != fill_value_point_hourly, y_all_hourly)
    end

    # Convert to kW/m^2
    y_all_hourly.Irradiance = y_all_hourly.Irradiance / 1000

    sort!(X_all_daily, [:DateTime, :Name])    # (timestep, patch, features)
    sort!(y_all_daily, [:DateTime, :Name])    # (timestep, patch, features)
    sort!(y_all_hourly, [:DateTime, :Name])   # (timestep, patch, features)

    println("\nDataset downloaded 🙂🙂🙂\n")

    # Show summary statistics
    println(describe(X_all_daily, :mean, :std, :median, :min, :max))
    println(describe(y_all_daily, :mean, :std, :median, :min, :max))
    println(describe(y_all_hourly, :mean, :std, :median, :min, :max))

    # write DataFrame out to CSV file
    CSV.write("dataset/X_all_daily.csv", X_all_daily)
    CSV.write("dataset/y_all_daily.csv", y_all_daily)
    CSV.write("dataset/y_all_hourly.csv", y_all_hourly)

    # Filter
    X_filtered = filter(:Name => n -> n == "Adani Green Energy Tamilnadu Limited", filter(:DateTime => d -> Dates.month(d) == 11, X_all_daily))
    Y_filtered = filter(:Name => n -> n == "Indira Paryavaran Bhawan", filter(:DateTime => d -> Dates.month(d) == 11, y_all_daily))
    # north - south
    # Indira Paryavaran Bhawan
    # Adani Green Energy Tamilnadu Limited

    # west - east
    # Bitta Solar Power Plant
    # Rewa Ultra Mega Solar

    Utils.create_heatmap(X_filtered, Y_filtered, round(Int, parsed_args["width"] * 2), round(Int, parsed_args["height"] * 2), "Irradiance")
    Utils.create_heatmap(X_filtered, Y_filtered, round(Int, parsed_args["width"] * 2), round(Int, parsed_args["height"] * 2), "Temp")
    Utils.create_heatmap(X_filtered, Y_filtered, round(Int, parsed_args["width"] * 2), round(Int, parsed_args["height"] * 2), "TempMin")
    Utils.create_heatmap(X_filtered, Y_filtered, round(Int, parsed_args["width"] * 2), round(Int, parsed_args["height"] * 2), "TempMax")
    Utils.create_heatmap(X_filtered, Y_filtered, round(Int, parsed_args["width"] * 2), round(Int, parsed_args["height"] * 2), "Humidity")
    Utils.create_heatmap(X_filtered, Y_filtered, round(Int, parsed_args["width"] * 2), round(Int, parsed_args["height"] * 2), "WindSpeed", windDir = true)
    Utils.create_heatmap(X_filtered, Y_filtered, round(Int, parsed_args["width"] * 2), round(Int, parsed_args["height"] * 2), "WindSpeedMin", windDir = true)
    Utils.create_heatmap(X_filtered, Y_filtered, round(Int, parsed_args["width"] * 2), round(Int, parsed_args["height"] * 2), "WindSpeedMax", windDir = true)
    Utils.create_heatmap(X_filtered, Y_filtered, round(Int, parsed_args["width"] * 2), round(Int, parsed_args["height"] * 2), "WindDirection", windDir = true)
    Utils.create_heatmap(X_filtered, Y_filtered, round(Int, parsed_args["width"] * 2), round(Int, parsed_args["height"] * 2), "Pressure")
end

# check the num. of threads
if Threads.nthreads() == 1
    println("Warning: The number of threads is only 1. It is recommended to use at least 2 threads.")
end

@time main()