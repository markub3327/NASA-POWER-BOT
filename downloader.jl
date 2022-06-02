module NASAPowerDownloader

using HTTP
using JSON



function download_regional(year, regional, mode, timeout=30)

    try
        r = HTTP.request(
            "GET", 
            "https://power.larc.nasa.gov/api/temporal/$(mode)/regional?start=$(year)0101&end=$(year)1231&latitude-min=$(regional.latitude_min)&latitude-max=$(regional.latitude_max)&longitude-min=$(regional.longitude_min)&longitude-max=$(regional.longitude_max)&community=re&parameters=ALLSKY_SFC_SW_DWN&time-standard=utc&format=json&header=true",
            readtimeout = timeout
        )
        j = JSON.parse(String(r.body))
        return j
    catch e
        # Too Many Requests
        if (e.status == 429)
            sleep(10)
            # println("Retrying download ♻️")
            return download_regional(year, regional, mode, timeout)
        else
            print("Error $(e)")
            exit(-1) 
        end
    end
end

function download_point(year, point, mode, timeout=30)

    try
        r = HTTP.request(
            "GET",
            "https://power.larc.nasa.gov/api/temporal/$(mode)/point?start=$(year)0101&end=$(year)1231&latitude=$(point.latitude)&longitude=$(point.longitude)&community=re&parameters=ALLSKY_SFC_SW_DWN&time-standard=utc&format=json&header=true",
            readtimeout = timeout
        )
        j = JSON.parse(String(r.body))
        return j
    catch e
        # Too Many Requests
        if (e.status == 429)
            sleep(10)
            # println("Retrying download ♻️")
            return download_point(year, point, mode, timeout)
        else
            print("Error $(e)")
            exit(-1) 
        end
    end
end
end