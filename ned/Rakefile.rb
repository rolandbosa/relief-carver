#!/usr/bin/env rake

require 'zip/zipfilesystem'

rule '.tif' => [ '.flt' ] do |t|
  sector = File.basename(t.name, '.tif')
  if File.size(t.source) == 0 then
    puts "FLT file too small - assuming non-existent tile..."
  else
    puts "Converting float data to GeoTiff for sector #{sector}..."
    system('gdalwarp', "#{sector}.flt", "#{sector}.tif")
  end
end

rule '.flt' => [ '.zip' ] do |t|
  sector = File.basename(t.name, '.flt')
  if File.size(t.source) < 1000 then
    puts "File too small - assuming a 404 message from the server... Please check #{t.source}"
    File.open("#{sector}.flt", "w") { |flt| }
  else
    puts "Extracting float data for sector #{sector}..."
    File.delete("#{sector}.hdr") if File.exist?("#{sector}.hdr")
    File.delete("#{sector}.prj") if File.exist?("#{sector}.prj")
    Zip::ZipFile.open(t.source) do |zipfile|
      zipfile.extract "#{sector}/float#{sector}_13.flt", "#{sector}.flt"
      zipfile.extract "#{sector}/float#{sector}_13.hdr", "#{sector}.hdr"
    zipfile.extract "#{sector}/float#{sector}_13.prj", "#{sector}.prj"
    end
    puts "Fixing the header file..."
    File.open("#{sector}.hdr", "a") do |hdr|
      hdr.puts "nbits   32"
      hdr.puts "pixeltype float"
    end
  end
end

rule '.zip' do |t|
  puts "Downloading #{t.name}..."
  url = "http://tdds.cr.usgs.gov/ned/13arcsec/float/float_zips/#{t.name}"
  system("curl", "-O", url, "-C", "-")
end

def request(n, w)
  file "all.vrt" => [ "n#{n}w#{w}.tif" ]
end

task :enumTasks do |t|
  for w in (118..123) do
    for n in (36..38) do
      request n, w
    end
  end

  # entire US: -125..-58 23..50
end

desc "Downloads ZIP files and converts them to GeoTiff files"
task :default => [ :enumTasks, "all.vrt" ] do
  puts "Elevation complete."
end

file "all.vrt" do |t|
  puts "#{t.source}"
  system("gdalbuildvrt", "-overwrite", "all.vrt", *FileList['*.tif'])
end

task :yosemite_data do
  request 38,120
end

task :yosemite => [ :yosemite_data, "all.vrt" ] do
  puts "Creating yosemite.bmp"
  puts `gdalwarp -te -119.7075 37.6933 -119.504 37.7753 -overwrite -of gtiff all.vrt yosemite.tif`
  puts `gdal_translate -of PNG -ot BYTE -scale yosemite.tif yosemite.png`
  File.delete("yosemite.tif") if File.exist?("yosemite.tif")
end

task :sanfrancisco_data do
  request 38,123
end

task :sanfrancisco => [ :sanfrancisco_data, "all.vrt" ] do
  puts "Creating sf.png (San Francisco)"
  puts `gdalwarp -te -122.5449 37.6894 -122.3426 37.8361 -overwrite -of gtiff all.vrt sf.tif`
  puts `gdal_translate -of PNG -ot BYTE -scale sf.tif sf.png`
  # Create a version which scales the input from 0..height to the
  # output byte 0..255. The higher the height is, the less detail is
  # visible, however, this might fix the 'plateau'-ing that eric
  # noticed:
  [ 200, 300, 400, 500, 600 ].each do |height|
    puts `gdal_translate -of PNG -ot BYTE -scale 0 #{height} sf.tif sf#{height}.png`
  end
  File.delete("sf.tif") if File.exist?("sf.tif")
end
