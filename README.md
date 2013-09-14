Relief-Carver: Convert elevation data into G-code
=============

Simple and slow, just using Ruby. Generates a big file with lots of
G-code codes.

This version allows the carving direction to be flipped, so that the
cutting tool "bites" into the material. This should make for a better
cut.

This version also outputs the various slices into individual files (is
this really useful?).


Installation:
------------

First, make sure you have a decent ruby:

    $ ruby --version

You should see something around 1.9.3 or higher.

Get Bundler:

    $ gem install bundler

Let Bundler get the required gems

    $ bundle install

And finally, edit carver.rb top section and adjust the parameters as needed:

    $ emacs carver.rb

Generate the data by running the script:

    $ ./carver.rb

There we go, Bob's your uncle.


Things to do:
------------

Use less global variables and write better Ruby code (this code is far
from 'nice').


The images
----------

In the 'ned' subdirectory, you'll find a Rakefile, which can be used
to create the PNGs of San Francisco and Yosemite.

To create them, use the following command line:

    rake yosemite

and

    rake sanfrancisco

The rakefile requires a bunch of dependencies, amongst others:

  * Data is downloaded using *curl*.

  * The zipped data is unpacked using the *rubyzip* gem.

  * The unzipped data is converted and processed using the Gdal
    suite. (see http://www.gdal.org)
