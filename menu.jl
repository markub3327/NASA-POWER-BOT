module Menu

    using ArgParse

    function main_menu()
        s = ArgParseSettings()

        @add_arg_table! s begin
            "--start", "--year-start"
                arg_type = Int
                help = "Year start"
                required = true
        
            "--end", "--year-end"
                arg_type = Int
                help = "Year end"
                required = true

            "--width", "--area-width"
                arg_type = Float32
                help = "Area width"
                required = true

            "--height", "--area-height"
                arg_type = Float32
                help = "Area height"
                required = true

            "--timeout"
                arg_type = Int
                default = 300  # 5 minutes
                help = "Timeout"

        end
        
        args = parse_args(s)

        # check the arguments correctness
        @assert args["start"] <= args["end"]

        return args
    end

end