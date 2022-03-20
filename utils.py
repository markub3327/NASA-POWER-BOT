def num_of_leap_years(year):
    return (year // 4) - (year // 100) + (year // 400)


def num_of_leap_years_in_range(start, end):
    start -= 1
    return num_of_leap_years(end) - num_of_leap_years(start)


def get_area(loc, width, height):
    offset_x = width / 2
    offset_y = height / 2
    return (
        round(loc[0] - offset_x, 6),
        round(loc[0] + offset_x, 6),
        round(loc[1] - offset_y, 6),
        round(loc[1] + offset_y, 6),
    )
