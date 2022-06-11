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
using CairoMakie

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

                        wd_rad = deg2rad(wd[2])
                        push!(X[time], ws[2]*cos(wd_rad - (pi/2)))       # copying
                        push!(X[time], ws[2]*sin(wd_rad - (pi/2)))       # copying
                        push!(X[time], ws_min[2]*cos(wd_rad - (pi/2)))   # copying
                        push!(X[time], ws_min[2]*sin(wd_rad - (pi/2)))   # copying
                        push!(X[time], ws_max[2]*cos(wd_rad - (pi/2)))   # copying
                        push!(X[time], ws_max[2]*sin(wd_rad - (pi/2)))   # copying

                        push!(X[time], p[2])        # copying
                    else
                        wd_rad = deg2rad(wd[2])
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
                            ws[2]*cos(wd_rad - (pi/2)),
                            ws[2]*sin(wd_rad - (pi/2)),
                            ws_min[2]*cos(wd_rad - (pi/2)),
                            ws_min[2]*sin(wd_rad - (pi/2)),
                            ws_max[2]*cos(wd_rad - (pi/2)),
                            ws_max[2]*sin(wd_rad - (pi/2)),
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

    # Region Heatmap
    data1_1 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data2_1 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data1_2 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data2_2 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data1_3 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data2_3 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data1_4 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data2_4 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data1_5 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data2_5 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data1_6 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data2_6 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data1_7 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data2_7 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data1_8 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data2_8 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data1_9 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data2_9 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data1_10 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    data2_10 = Array{Float32}(undef, round(Int, parsed_args["height"] * 2), round(Int, parsed_args["width"] * 2))
    k = 1
    X_all_daily_filtered = filter(:DateTime => d -> Dates.month(d) == 1, X_all_daily)
    y_all_daily_filtered = filter(:DateTime => d -> Dates.month(d) == 1, y_all_daily)
    for i::Int in 1:parsed_args["height"] * 2
        for j::Int in 1:parsed_args["width"] * 2
            data1_1[i, j] = cor(X_all_daily_filtered[!, "Irradiance$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data2_1[i, j] = corspearman(X_all_daily_filtered[!, "Irradiance$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data1_2[i, j] = cor(X_all_daily_filtered[!, "Temp$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data2_2[i, j] = corspearman(X_all_daily_filtered[!, "Temp$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data1_3[i, j] = cor(X_all_daily_filtered[!, "TempMin$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data2_3[i, j] = corspearman(X_all_daily_filtered[!, "TempMin$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data1_4[i, j] = cor(X_all_daily_filtered[!, "TempMax$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data2_4[i, j] = corspearman(X_all_daily_filtered[!, "TempMax$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data1_5[i, j] = cor(X_all_daily_filtered[!, "Humidity$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data2_5[i, j] = corspearman(X_all_daily_filtered[!, "Humidity$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data1_6[i, j] = cor(X_all_daily_filtered[!, "WindSpeed$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data2_6[i, j] = corspearman(X_all_daily_filtered[!, "WindSpeed$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data1_7[i, j] = cor(X_all_daily_filtered[!, "WindSpeedMin$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data2_7[i, j] = corspearman(X_all_daily_filtered[!, "WindSpeedMin$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data1_8[i, j] = cor(X_all_daily_filtered[!, "WindSpeedMax$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data2_8[i, j] = corspearman(X_all_daily_filtered[!, "WindSpeedMax$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data1_9[i, j] = cor(X_all_daily_filtered[!, "WindDirection$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data2_9[i, j] = corspearman(X_all_daily_filtered[!, "WindDirection$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data1_10[i, j] = cor(X_all_daily_filtered[!, "Pressure$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            data2_10[i, j] = corspearman(X_all_daily_filtered[!, "Pressure$(k)"], y_all_daily_filtered[!, "Irradiance"]) * 100
            k = k + 1
        end
    end
    
    fig = Figure(resolution = (1000, 2000))
    xs = LinRange(1, 5, 5)
    ys = LinRange(1, 5, 5)
    ax1, hm1 = heatmap(fig[1, 1], data1_1) #, c = :amp, dpi = 600)
    ax1.title = "Irradiance \"Region - Point\" Pearson correlation"
    ax1.xlabel = "Longitude"
    ax1.ylabel = "Latitude"
    ax2, hm2 = heatmap(fig[1, 3], data2_1) #, c = :amp, dpi = 600)
    ax2.title = "Irradiance \"Region - Point\" Spearman correlation"
    ax2.xlabel = "Longitude"
    ax2.ylabel = "Latitude"
    ax3, hm3 = heatmap(fig[2, 1], data1_2) #, c = :amp, dpi = 600)
    ax3.title = "Temperature \"Region - Point\" Pearson correlation"
    ax3.xlabel = "Longitude"
    ax3.ylabel = "Latitude"
    ax4, hm4 = heatmap(fig[2, 3], data2_2) #, c = :amp, dpi = 600)
    ax4.title = "Temperature \"Region - Point\" Spearman correlation"
    ax4.xlabel = "Longitude"
    ax4.ylabel = "Latitude"
    ax5, hm5 = heatmap(fig[3, 1], data1_3) #, c = :amp, dpi = 600)
    ax5.title = "Temperature Min \"Region - Point\" Pearson correlation"
    ax5.xlabel = "Longitude"
    ax5.ylabel = "Latitude"
    ax6, hm6 = heatmap(fig[3, 3], data2_3) #, c = :amp, dpi = 600)
    ax6.title = "Temperature Min \"Region - Point\" Spearman correlation"
    ax6.xlabel = "Longitude"
    ax6.ylabel = "Latitude"
    ax7, hm7 = heatmap(fig[4, 1], data1_4) #, c = :amp, dpi = 600)
    ax7.title = "Temperature Max \"Region - Point\" Pearson correlation"
    ax7.xlabel = "Longitude"
    ax7.ylabel = "Latitude"
    ax8, hm8 = heatmap(fig[4, 3], data2_4) #, c = :amp, dpi = 600)
    ax8.title = "Temperature Max \"Region - Point\" Spearman correlation"
    ax8.xlabel = "Longitude"
    ax8.ylabel = "Latitude"
    ax9, hm9 = heatmap(fig[5, 1], data1_5) #, c = :ice, dpi = 600)
    ax9.title = "Humidity \"Region - Point\" Pearson correlation"
    ax9.xlabel = "Longitude"
    ax9.ylabel = "Latitude"
    ax10, hm10 = heatmap(fig[5, 3], data2_5) #, c = :ice, dpi = 600)
    ax10.title = "Humidity \"Region - Point\" Spearman correlation"
    ax10.xlabel = "Longitude"
    ax10.ylabel = "Latitude"
    ax11, hm11 = heatmap(fig[6, 1], data1_10) #, c = :ice, dpi = 600)
    ax11.title = "Pressure \"Region - Point\" Pearson correlation"
    ax11.xlabel = "Longitude"
    ax11.ylabel = "Latitude"
    ax12, hm12 = heatmap(fig[6, 3], data2_10) #, c = :ice, dpi = 600)
    ax12.title = "Pressure \"Region - Point\" Spearman correlation"
    ax12.xlabel = "Longitude"
    ax12.ylabel = "Latitude"
    ax13, hm13 = heatmap(fig[7, 1], data1_6) #, c = :balance, dpi = 600)
    ax13.title = "Wind speed \"Region - Point\" Pearson correlation"
    ax13.xlabel = "Longitude"
    ax13.ylabel = "Latitude"
    ax14, hm14 = heatmap(fig[7, 3], data2_6) #, c = :balance, dpi = 600)
    ax14.title = "Wind speed \"Region - Point\" Spearman correlation"
    ax14.xlabel = "Longitude"
    ax14.ylabel = "Latitude"
    ax15, hm15 = heatmap(fig[8, 1], data1_7) #, c = :amp, dpi = 600)
    ax15.title = "Wind speed Min \"Region - Point\" Pearson correlation"
    ax15.xlabel = "Longitude"
    ax15.ylabel = "Latitude"
    ax16, hm16 = heatmap(fig[8, 3], data2_7) #, c = :amp, dpi = 600)
    ax16.title = "Wind speed Min \"Region - Point\" Spearman correlation"
    ax16.xlabel = "Longitude"
    ax16.ylabel = "Latitude"
    ax17, hm17 = heatmap(fig[9, 1], data1_8) #, c = :amp, dpi = 600)
    ax17.title = "Wind speed Max \"Region - Point\" Pearson correlation"
    ax17.xlabel = "Longitude"
    ax17.ylabel = "Latitude"
    ax18, hm18 = heatmap(fig[9, 3], data2_8) #, c = :amp, dpi = 600)
    ax18.title = "Wind speed Max \"Region - Point\" Spearman correlation"
    ax18.xlabel = "Longitude"
    ax18.ylabel = "Latitude"
    ax19, hm19 = heatmap(fig[10, 1], data1_9) #, c = :amp, dpi = 600)
    ax19.title = "Wind direction \"Region - Point\" Pearson correlation"
    ax19.xlabel = "Longitude"
    ax19.ylabel = "Latitude"
    ax20, hm20 = heatmap(fig[10, 3], data2_9) #, c = :amp, dpi = 600)
    ax20.title = "Wind direction \"Region - Point\" Spearman correlation"
    ax20.xlabel = "Longitude"
    ax20.ylabel = "Latitude"

    Colorbar(fig[1, 2], hm1, label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[1, 4], hm2,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[2, 2], hm3,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[2, 4], hm4,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[3, 2], hm5,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[3, 4], hm6,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[4, 2], hm7,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[4, 4], hm8,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[5, 2], hm9,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[5, 4], hm10,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[6, 2], hm11,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[6, 4], hm12,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[7, 2], hm13,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[7, 4], hm14,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[8, 2], hm15,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[8, 4], hm16,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[9, 2], hm17,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[9, 4], hm18,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[10, 2], hm19,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)
    Colorbar(fig[10, 4], hm20,  label="Percent [%]", flipaxis = false) #  limits = (0, 10)

    Wx = mean(Matrix(X_all_daily_filtered[!, ["WindX$(k)" for k in 1:parsed_args["width"] * 2 * parsed_args["height"] * 2]]), dims=1)
    Wy = mean(Matrix(X_all_daily_filtered[!, ["WindY$(k)" for k in 1:parsed_args["width"] * 2 * parsed_args["height"] * 2]]), dims=1)
    WxMin = mean(Matrix(X_all_daily_filtered[!, ["WindXMin$(k)" for k in 1:parsed_args["width"] * 2 * parsed_args["height"] * 2]]), dims=1)
    WyMin = mean(Matrix(X_all_daily_filtered[!, ["WindYMin$(k)" for k in 1:parsed_args["width"] * 2 * parsed_args["height"] * 2]]), dims=1)
    WxMax = mean(Matrix(X_all_daily_filtered[!, ["WindXMax$(k)" for k in 1:parsed_args["width"] * 2 * parsed_args["height"] * 2]]), dims=1)
    WyMax = mean(Matrix(X_all_daily_filtered[!, ["WindYMax$(k)" for k in 1:parsed_args["width"] * 2 * parsed_args["height"] * 2]]), dims=1)

    arrows!(fig[7, 1], xs, ys, Wx, Wy, arrowsize = 15, lengthscale = 0.25)
    arrows!(fig[7, 3], xs, ys, Wx, Wy, arrowsize = 15, lengthscale = 0.25)
    arrows!(fig[8, 1], xs, ys, WxMin, WyMin, arrowsize = 15, lengthscale = 0.25)
    arrows!(fig[8, 3], xs, ys, WxMin, WyMin, arrowsize = 15, lengthscale = 0.25)
    arrows!(fig[9, 1], xs, ys, WxMax, WyMax, arrowsize = 15, lengthscale = 0.25)
    arrows!(fig[9, 3], xs, ys, WxMax, WyMax, arrowsize = 15, lengthscale = 0.25)
    arrows!(fig[10, 1], xs, ys, Wx, Wy, arrowsize = 15, lengthscale = 0.25)
    arrows!(fig[10, 3], xs, ys, Wx, Wy, arrowsize = 15, lengthscale = 0.25)

    save("imgs/region.png", fig)
end

# check the num. of threads
if Threads.nthreads() == 1
    println("Warning: The number of threads is only 1. It is recommended to use at least 2 threads.")
end

@time main()