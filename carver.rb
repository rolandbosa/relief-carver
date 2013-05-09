#!/usr/bin/env ruby

require 'chunky_png'
require 'ruby-progressbar'
require 'pp'

# Which relief are we carving?
# $Relief = 'sf'
$Relief = 'yosemite'

# Big picture / high resolution
# $ImageFilename = "#{$Relief}.png"

# Small picture / low resolution
$ImageFilename = "#{$Relief}-mini.png"

# Output filename prefix
$GCodeFilenamePrefix = "#{$Relief}-gcode"

# All measurements in inches, unless specified otherwise.

# How far the block starts from the origin
$OffsetX     = 2.00
$OffsetY     = 2.00

# dimensions of the block
$BlockX      = 5.00
$BlockY      = 3.00
$BlockZ      = 1.50

# How the relief gets carved
$ReliefMinZ  = 1.00 / 4.0
$ReliefMaxZ  = $BlockZ - 1.0 / 16.00

# The radius of the carving tool (1/4" diameter == 1/8" radius)
$CarveRadius = 1.00 /  8.00

# How deep the tool can be to carve out material (how much material
# can be carved at a given depth) - determines how many times we have
# to pass over a spot to reach maximum penetration depth...
$CarveDepth  = 1.00 /  8.00

# Height at which to taxi around
$TaxiZ       = 2.00

# How fast the tool moves during carving and while at
# taxi-height. (G-code: F)
$CarveSpeed  = 10.0
$TaxiSpeed   = 30.0

# Direction of cutting of the X- and Y-axis - if the tool does not
# 'bite' into the material, you need to reverse one of these
# directions.
$ReverseX    = false
$ReverseY    = true

# Flipping the image, if it comes out mirrored, or upside down
$FlipX       = true
$FlipY       = false

# Tiny amount to leave on surface when doing slice N, which will be
# shaved off during slice N+1. Makes any visible marks for slices
# disappear.
$SliceShave  = 0.05

#-------

$ReliefRange = $ReliefMaxZ - $ReliefMinZ

# some range checks...
raise "$ReliefMinZ must be smaller than $ReliefMaxZ!" if $ReliefMinZ >= $ReliefMaxZ
raise "$BlockX should be a tad bigger (for numerical stability)!" if $BlockX < 0.01
raise "$BlockY should be a tad bigger (for numerical stability)!" if $BlockY < 0.01
raise "$SliceShave should be 0.0 or positive!" if $SliceShave < 0.0
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

$prevX = nil
$prevY = nil
$prevZ = nil
$prevS = nil

def goto(file, x, y, z, s)
  x += $OffsetX
  y += $OffsetY

  line = []
  if x != $prevX then
    line << "X#{x}"
    $prevX = x
  end

  if y != $prevY then
    line << "Y#{y}"
    $prevY = y
  end

  if z != $prevZ then
    line << "Z#{z}"
    $prevZ = z
  end

  if s != $prevS then
    line << "F#{s}"
    $prevS = s
  end

  file.puts line.join(' ') unless line.empty?
end

def maxHeight(x, y)
  x = $BlockX - x if $FlipX
  y = $BlockY - y if $FlipY
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
STDERR.puts "One pixel of the source image corresponds to #{1.0 / $aspect} inches."
STDERR.puts "Advancing by 1/4 of the tool radius amounts to #{$CarveRadius / 4.0} inches."
carveStep = [1.0 / $aspect, $CarveRadius / 4.0].max
STDERR.puts "Using a carver step size of: #{carveStep} inches."
stepsX = ($BlockX / carveStep).ceil
stepsY = ($BlockY / carveStep).ceil
totalSteps = stepsX * stepsY
STDERR.puts "Using a shaving size of #{$SliceShave} inches." if 0.0 < $SliceShave

# lets do it!
while 0 < sliceCount do
  progress = ProgressBar.create(:format => '%e |%b>>%i| %P%% %c/%C %t',
                                :title => "Slice #{sliceCount}",
                                :total => totalSteps)
  File.open("#{$GCodeFilenamePrefix}-#{sliceCount}.txt", "w") do |file|
    goto file, -$OffsetX, -$OffsetY, $TaxiZ, $TaxiSpeed
    sliceCount -= 1
    sliceFloor = $ReliefMinZ + sliceCount * $CarveDepth
    shaving = sliceCount * $SliceShave
    x = 0
    while x < stepsX do
      carveX = ($ReverseX ? ((stepsX - 1) - x) : x) * carveStep
      y = 0
      carveY = ($ReverseY ? ((stepsY - 1) - y) : y) * carveStep
      goto file, carveX, carveY, $TaxiZ, $TaxiSpeed
      while y < stepsY do
        redValue = maxHeight(carveX, carveY)
        reliefZ = $ReliefMinZ + ($ReliefRange * (redValue - $minRed)) / $rangeRed
        if reliefZ < sliceFloor then reliefZ = sliceFloor end
        reliefZ += shaving
        goto file, carveX, carveY, reliefZ, $CarveSpeed
        progress.increment if progress.progress < (totalSteps - 1)
        y += 1
        carveY = ($ReverseY ? ((stepsY - 1) - y) : y) * carveStep
      end
      goto file, carveX, carveY, $TaxiZ, $TaxiSpeed
      x += 1
    end
    progress.finish
    # go back to rest position
    STDERR.puts "Moving back to origin..."
    goto file, -$OffsetX, -$OffsetY, $TaxiZ, $TaxiSpeed
    goto file, -$OffsetX, -$OffsetY, 0.0, $TaxiSpeed
  end
end
