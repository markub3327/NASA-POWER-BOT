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
end