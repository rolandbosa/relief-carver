#!/usr/bin/env ruby

require 'chunky_png'
require 'ruby-progressbar'
require 'pp'


# Big picture / high resolution
$ImageFilename = 'sf.png'

# Small picture / low resolution
# $ImageFilename = 'mini.png'

# the file that will be filled with GCodes
$GCodeFilename = 'data.txt'

# All measurements in inches, unless specified otherwise.

# How far the block starts from the origin
$OffsetX     = 2.00
$OffsetY     = 2.00

# dimensions of the block
$BlockX      = 10.00
$BlockY      = 5.00
$BlockZ      = 1.00

# How the relief gets carved
$ReliefMinZ  =  1.00 / 16.00
$ReliefMaxZ  = 15.00 / 16.00

# The radius of the carving tool (1/2" diameter == 1/4" radius)
$CarveRadius = 1.00 /  4.00

# How deep the tool can be to carve out material (how much material
# can be carved at a given depth) - determines how many times we have
# to pass over a spot to reach maximum penetration depth...
$CarveDepth  = 1.00 /  4.00

def outputGCode(file, x, y, z)
  # provide an implementation which outputs the proper GCode to move
  # the drill to the specified position
  file.puts "#{x},#{y},#{z}"
end

#-------

# Height at which to taxi around
$TaxiZ       = 2.00
$ReliefRange = $ReliefMaxZ - $ReliefMinZ

# some range checks...
raise "$ReliefMinZ must be smaller than $ReliefMaxZ!" if $ReliefMinZ >= $ReliefMaxZ
raise "$BlockX should be a tad bigger (for numerical stability)!" if $BlockX < 0.01
raise "$BlockY should be a tad bigger (for numerical stability)!" if $BlockY < 0.01
STDERR.puts "Warning - highest relief is higher than block!" if $BlockZ < $ReliefMaxZ

#-------

def pixelValue(c)
  ChunkyPNG::Color.r(c)
end

STDERR.puts "Loading image...#{$ImageFilename}"
$png = ChunkyPNG::Image.from_file($ImageFilename)
$ImageX = $png.width.to_f
$ImageY = $png.height.to_f
STDERR.puts "Loaded map with X: #{$png.width} and Y: #{$png.height}"

$minRed = 255
$maxRed = 0
$png.pixels.each do |c|
  red = pixelValue(c)
  if red < $minRed then $minRed = red end
  if red > $maxRed then $maxRed = red end
end
$rangeRed = $maxRed - $minRed

STDERR.puts "Range of red channel: #{$minRed}..#{$maxRed} (#{$rangeRed} levels)"

block_aspect_ratio = $BlockX / $BlockY
image_aspect_ratio = $ImageX / $ImageY
if image_aspect_ratio < block_aspect_ratio then
  $aspect = $ImageX / $BlockX
else
  $aspect = $ImageY / $BlockY
end

$BlockXPixels = $BlockX * $aspect
$BlockYPixels = $BlockY * $aspect
$ImageOffsetX = (($ImageX - $BlockXPixels) / 2).to_i
$ImageOffsetY = (($ImageY - $BlockYPixels) / 2).to_i

STDERR.puts "Block Aspect Ratio: #{block_aspect_ratio}"
STDERR.puts "Image Aspect Ratio: #{image_aspect_ratio}"
STDERR.puts "Inch2PixelCoefficient: #{$aspect}"
STDERR.puts "Pixels on block: #{$BlockXPixels}  #{$BlockYPixels}"
STDERR.puts "Skipped Pixels: #{$ImageOffsetX} #{$ImageOffsetY}"

def goto(file, x, y, z)
  x += $OffsetX
  y += $OffsetY
  outputGCode(file, x, y, z)
end

def maxHeight(x, y)
  cx = ($ImageOffsetX + x * $aspect).to_i
  cy = ($ImageOffsetY + y * $aspect).to_i
  radius = ($CarveRadius * $aspect).ceil
  squared_radius = radius * radius
  range = (-radius..radius)
  result = $minRed
  range.each do |xr|
    range.each do |yr|
      if (xr * xr + yr * yr) < squared_radius then
        # inside round tool, now make sure it's inside the image for the lookup
        x = cx + xr
        y = cy + yr
        if (0 <= x) and (x < $ImageX) and (0 <= y) and (y < $ImageY) then
          red = pixelValue($png[x, y])
          if red > result then result = red end
        end
      end
    end
  end
  result
end

# amount of material to remove
total_carve_amount = $BlockZ - $ReliefMinZ
sliceCount = (total_carve_amount / $CarveDepth).ceil

# carving increment: either advance at least one pixel of the
# heightmap (1.0 / $aspect), or a quarter of the current carving tool
# - do you have any better ideas?
carveStep = [1.0 / $aspect, $CarveRadius / 4.0].max
STDERR.puts "Using a carver step size of: #{carveStep} inches."
totalSteps = (($BlockX / carveStep).ceil * ($BlockY / carveStep).ceil).to_i

# lets do it!
File.open($GCodeFilename, "w") do |file|
  goto file, -$OffsetX, -$OffsetY, $TaxiZ
  while 0 < sliceCount do
    progress = ProgressBar.create(:format => '%e |%b>>%i| %P%% %c/%C %t',
                                  :title => "Slice #{sliceCount}",
                                  :total => totalSteps)
    sliceCount -= 1
    sliceFloor = $ReliefMinZ + sliceCount * $CarveDepth
    carveX = 0.0
    while carveX < $BlockX do
      carveY = 0.0
      goto file, carveX, carveY, $TaxiZ
      while carveY < $BlockY do
        redValue = maxHeight(carveX, carveY)
        reliefZ = $ReliefMinZ + ($ReliefRange * (redValue - $minRed)) / $rangeRed
        if reliefZ < sliceFloor then reliefZ = sliceFloor end
        goto file, carveX, carveY, reliefZ
        progress.increment if progress.progress < (totalSteps - 1)
        carveY += carveStep
      end
      goto file, carveX, carveY, $TaxiZ
      carveX += carveStep
    end
    progress.finish
  end

  # go back to rest position
  STDERR.puts "Moving back to origin..."
  goto file, -$OffsetX, -$OffsetY, $TaxiZ
  goto file, -$OffsetX, -$OffsetY, 0.0
end
