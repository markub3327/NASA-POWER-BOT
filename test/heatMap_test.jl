width = 3
height = 3

dir = [225 180 135 270 0 90 315 360 45]

Wy = -sind.(mod.(-dir .+ 90, 360))
Wx = -cosd.(mod.(-dir .+ 90, 360))

data1 = Array{Float32}(undef, round(Int, width), round(Int, height))

k = 1
for j::Int in 1:height
    for i::Int in 1:width
        data1[i, j] = k
        k = k + 1
    end
end
fig, ax, hm = heatmap(data1)
Colorbar(fig[:, end+1], hm)

xs = 1:width
ys = 1:height
arrows!(fig[:, 1], xs, ys, Wx, Wy, arrowsize = 30, lengthscale = 0.2, linewidth = 3)
display(fig)