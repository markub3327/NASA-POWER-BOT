module  Utils

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
        return (
            round(loc[1] - offset_x, digits = 6),
            round(loc[1] + offset_x, digits = 6),
            round(loc[2] - offset_y, digits = 6),
            round(loc[2] + offset_y, digits = 6),
        )
    end
end