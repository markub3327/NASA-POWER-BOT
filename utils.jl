module  Utils
    using GLMakie
    using Dates
    using Statistics
    using StatsBase
    using EnergyStatistics

    struct Region
        latitude_min
        latitude_max
        longitude_min
        longitude_max
    end

    struct Point
        latitude
        longitude
    end

    function get_area(loc, width, height)
        offset_x = width / 2
        offset_y = height / 2
        return Region(
            round(loc[1] - offset_x, digits = 6),
            round(loc[1] + offset_x, digits = 6),
            round(loc[2] - offset_y, digits = 6),
            round(loc[2] + offset_y, digits = 6),
        )
    end

    function intersection_over_union(boxA::Region, boxB::Region)
        # determine the (x, y)-coordinates of the intersection rectangle
        xA = max(boxA.latitude_min, boxB.latitude_min)
        yA = max(boxA.longitude_min, boxB.longitude_min)
        xB = min(boxA.latitude_max, boxB.latitude_max)
        yB = min(boxA.longitude_max, boxB.longitude_max)

        # compute the area of intersection rectangle
        interArea = max(0, (xB - xA)) * max(0, (yB - yA))
        if interArea == 0
            return 0
        end

        # compute the area of both the prediction and ground-truth
        # rectangles
        boxAArea = abs((boxA.latitude_max - boxA.latitude_min) * (boxA.longitude_max - boxA.longitude_min))
        boxBArea = abs((boxB.latitude_max - boxB.latitude_min) * (boxB.longitude_max - boxB.longitude_min))

        # compute the intersection over union by taking the intersection
        # area and dividing it by the sum of prediction + ground-truth
        # areas - the interesection area
        iou = interArea / (boxAArea + boxBArea - interArea)

        # return the intersection over union value
        return iou
    end

    #my_pseudolog10(x) = sign(x) * exp(abs(x) + 1)

    function set_colormap!(hm)
        if hm.colorrange[][1] >= 0
            #hm.colorrange[] = (0, 1) .* maximum(abs, hm.colorrange[])
            hm.colormap = cgrad(:amp) #, scale = my_pseudolog10)
        else
            if hm.colorrange[][2] > 0
                hm.colorrange[] = (-1, 1) .* maximum(abs, hm.colorrange[])
                hm.colormap = :balance
            else
                #hm.colorrange[] = (-1, 0) .* maximum(abs, hm.colorrange[])
                hm.colormap = cgrad(:ice) #, scale = my_pseudolog10)
            end
        end

        #println(hm.colorrange[][1], ", ", hm.colorrange[][2])
    end

    function create_heatmap(X, Y, width, height, colName; windDir = false)
        data = Array{Float32}(undef, width, height)

        k = 1
        for j::Int in 1:height
            for i::Int in 1:width
                data[i, j] = dcor(X[!, "$(colName)$(k)"], Y[!, "Irradiance"]) * 100
                k = k + 1
            end
        end

        fig = Figure(resolution = (1720, 600))

        Colorbar(fig[1, 4], hm2, label="Percent [%]")
        ax3, hm3 = heatmap(fig[1, 5], data)
        ax3.title = "$(colName) - Distance correlation"
        ax3.xlabel = "Longitude"
        ax3.ylabel = "Latitude"
        set_colormap!(hm3)
        Colorbar(fig[1, 6], hm3, label="Percent [%]")

        if windDir
            xs = 1:width
            ys = 1:height
            dir = mean(Matrix(X[!, ["WindDirection$(k)" for k::Int in 1:width * height]]), dims=1)
            Wy = -sind.(mod.(-dir .+ 90, 360))
            Wx = -cosd.(mod.(-dir .+ 90, 360))

            arrows!(fig[1, 1], xs, ys, Wx, Wy, arrowsize = 15, lengthscale = 0.2, linewidth = 3)
            arrows!(fig[1, 3], xs, ys, Wx, Wy, arrowsize = 15, lengthscale = 0.2, linewidth = 3)
            arrows!(fig[1, 5], xs, ys, Wx, Wy, arrowsize = 15, lengthscale = 0.2, linewidth = 3)
        end

        save("imgs/$(colName).png", fig)
    end
end