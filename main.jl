include("./downloader.jl")
include("./utils.jl")
include("./menu.jl")

using Statistics
using StatsBase
using Base.Threads
using Dates
using DataFrames
using CSV
using YAML
using ProgressMeter
using Plots
using StatsPlots
gr(size=(2000, 2000))

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
                if iou > 0.4
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
        MonthCos = Float32[],
        DaySin = Float32[],
        DayCos = Float32[],
        Name = String[],
        Latitude = Float32[],
        Longitude = Float32[]
    ) for _ in 1:nthreads()]
    for i in 1:nthreads()
        for j::Int in 1:parsed_args["width"] * 2 * parsed_args["height"] * 2
            df_regional_daily[i][!, "Value$(j)"] = Float32[]
        end
    end
    df_point_daily = [ DataFrame(
        DateTime = Date[],
        MonthSin = Float32[],
        MonthCos = Float32[],
        DaySin = Float32[],
        DayCos = Float32[],
        Name = String[],
        Latitude = Float32[],
        Longitude = Float32[], 
        Irradiance = Float32[]
    ) for _ in 1:nthreads()]
    df_point_hourly = [ DataFrame(
        DateTime = DateTime[],
        MonthSin = Float32[],
        MonthCos = Float32[],
        DaySin = Float32[],
        DayCos = Float32[],
        HourSin = Float32[],
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
    @threads for year in parsed_args["start"]:parsed_args["end"]
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
                for (t, value) in irradiance
                    if haskey(X, t)
                        push!(X[t], value)        # copying
                    else
                        X[t] = [value]            # creating
                    end
                end
            end
            #println(X)

            for (t, value) in X
                t = Date(t, "yyyymmdd")
                push!(df_regional_daily[threadid()], [
                    t,
                    sinpi(month(t) / MONTH_PERIOD * 2),
                    cospi(month(t) / MONTH_PERIOD * 2),
                    sinpi(dayofyear(t) / DAY_PERIOD * 2),
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
                    cospi(month(t) / MONTH_PERIOD * 2),
                    sinpi(dayofyear(t) / DAY_PERIOD * 2),
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
                        cospi(month(t) / MONTH_PERIOD * 2),
                        sinpi(dayofyear(t) / DAY_PERIOD * 2),
                        cospi(dayofyear(t) / DAY_PERIOD * 2),
                        sinpi(hour(t) / HOUR_PERIOD * 2),
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
    if fill_value_regional != nothing
        for j::Int in 1:parsed_args["width"] * 2 * parsed_args["height"] * 2
            X_all_daily = filter("Value$(j)" => v -> v != fill_value_regional, X_all_daily)
        end    
    end
    if fill_value_point_daily != nothing
        y_all_daily = filter(:Irradiance => v -> v != fill_value_point_daily, y_all_daily)
    end
    if fill_value_point_hourly != nothing
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
    
    # Plotting density plot
    # p1 = @df X_all_daily density(
    #     :Latitude,
    #     title="Distribution of Latitude",
    #     xlab = "Latitude",
    #     ylab = "Distribution"
    # )
    # p2 = @df X_all_daily density(
    #     :Longitude,
    #     title="Distribution of Longitude",
    #     xlab = "Longitude",
    #     ylab = "Distribution"
    # )
    # p3 = @df X_all_daily density(
    #     :Value1,
    #     title="Distribution of Solar Irradiance",
    #     xlab = "Solar Irradiance",
    #     ylab = "Distribution"
    # )
    # p4 = @df X_all_daily plot(
    #     :Value1,
    #     title = "Solar Irradiance",
    #     xlab = "Time",
    #     ylab = "Solar Irradiance"
    # )
    # p5 = @df X_all_daily plot(
    #     :MonthSin,
    #     title = "Month sin feature",
    #     xlab = "Time",
    #     ylab = "Month sin"
    # )
    # p6 = @df X_all_daily plot(
    #     :MonthCos,
    #     title = "Month cos feature",
    #     xlab = "Time",
    #     ylab = "Month cos"
    # )
    # p7 = @df X_all_daily plot(
    #     :DaySin,
    #     title = "Day sin feature",
    #     xlab = "Time",
    #     ylab = "Day sin"
    # )
    # p8 = @df X_all_daily plot(
    #     :DayCos,
    #     title = "Day cos feature",
    #     xlab = "Time",
    #     ylab = "Day cos"
    # )
    # png(
    #     plot(p1, p2, p3, p4, p5, p6, p7, p8, layout = (4, 2), legend = false, dpi = 600),  # , title = "Regional daily dataset"
    #     "imgs/X_all_daily.png"
    # )

    # p9 = @df y_all_daily density(
    #     :Latitude,
    #     title="Distribution of Latitude",
    #     xlab = "Latitude",
    #     ylab = "Distribution"
    # )
    # p10 = @df y_all_daily density(
    #     :Longitude,
    #     title="Distribution of Longitude",
    #     xlab = "Longitude",
    #     ylab = "Distribution"
    # )
    # p11 = @df y_all_daily density(
    #     :Irradiance,
    #     title="Distribution of Solar Irradiance",
    #     xlab = "Solar Irradiance",
    #     ylab = "Distribution"
    # )
    # p12 = @df y_all_daily plot(
    #     :Irradiance,
    #     title = "Solar Irradiance",
    #     xlab = "Time",
    #     ylab = "Solar Irradiance"
    # )    
    # p13 = @df y_all_daily plot(
    #     :MonthSin,
    #     title = "Month sin feature",
    #     xlab = "Time",
    #     ylab = "Month sin"
    # )
    # p14 = @df y_all_daily plot(
    #     :MonthCos,
    #     title = "Month cos feature",
    #     xlab = "Time",
    #     ylab = "Month cos"
    # )
    # p15 = @df y_all_daily plot(
    #     :DaySin,
    #     title = "Day sin feature",
    #     xlab = "Time",
    #     ylab = "Day sin"
    # )
    # p16 = @df y_all_daily plot(
    #     :DayCos,
    #     title = "Day cos feature",
    #     xlab = "Time",
    #     ylab = "Day cos"
    # )
    # png(
    #     plot(p9, p10, p11, p12, p13, p14, p15, p16, layout = (4, 2), legend = false, dpi = 600),   # , title = "Point daily dataset"
    #     "imgs/y_all_daily.png"
    # )

    # p17 = @df y_all_hourly density(
    #     :Latitude,
    #     title="Distribution of Latitude",
    #     xlab = "Latitude",
    #     ylab = "Distribution"
    # )
    # p18 = @df y_all_hourly density(
    #     :Longitude,
    #     title="Distribution of Longitude",
    #     xlab = "Longitude",
    #     ylab = "Distribution"
    # )
    # p19 = @df y_all_hourly density(
    #     :Irradiance,
    #     title="Distribution of Solar Irradiance",
    #     xlab = "Solar Irradiance",
    #     ylab = "Distribution"
    # )
    # p20 = @df y_all_hourly plot(
    #     :Irradiance,
    #     title = "Solar Irradiance",
    #     xlab = "Time",
    #     ylab = "Solar Irradiance"
    # )    
    # p21 = @df y_all_hourly plot(
    #     :MonthSin,
    #     title = "Month sin feature",
    #     xlab = "Time",
    #     ylab = "Month sin"
    # )
    # p22 = @df y_all_hourly plot(
    #     :MonthCos,
    #     title = "Month cos feature",
    #     xlab = "Time",
    #     ylab = "Month cos"
    # )
    # p23 = @df y_all_hourly plot(
    #     :DaySin,
    #     title = "Day sin feature",
    #     xlab = "Time",
    #     ylab = "Day sin"
    # )
    # p24 = @df y_all_hourly plot(
    #     :DayCos,
    #     title = "Day cos feature",
    #     xlab = "Time",
    #     ylab = "Day cos"
    # )
    # p25 = @df y_all_hourly plot(
    #     :HourSin,
    #     title = "Hour sin feature",
    #     xlab = "Time",
    #     ylab = "Hour sin"
    # )
    # p26 = @df y_all_hourly plot(
    #     :HourCos,
    #     title = "Hour cos feature",
    #     xlab = "Time",
    #     ylab = "Hour cos"
    # )
    # png(
    #     plot(p17, p18, p19, p20, p21, p22, p23, p24, p25, p26, layout = (5, 2), legend = false, dpi = 600),  # , title = "Point hourly dataset"
    #     "imgs/y_all_hourly.png"
    # )

    # Region Heatmap
    data1 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data2 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    k = 1
    for i::Int in 1:parsed_args["height"] * 2
        for j::Int in 1:parsed_args["width"] * 2
            data1[i, j] = cor(X_all_daily[!, "Value$(k)"], y_all_daily[!, "Irradiance"])
            data2[i, j] = corspearman(X_all_daily[!, "Value$(k)"], y_all_daily[!, "Irradiance"])
            k = k + 1
        end
    end
    png(
        plot(
            plot(heatmap(data1, clim=(0.0, 1.0)), title = "Pearson Correlation Region - Point", xlab = "Latitude", ylab = "Longitude", dpi = 600),        
            plot(heatmap(data2, clim=(0.0, 1.0)), title = "Spearman Correlation Region - Point", xlab = "Latitude", ylab = "Longitude", dpi = 600),
            layout = (2, 1),
            legend = false,
            dpi = 600
        ),
        "imgs/region.png"
    )
end


@time main()