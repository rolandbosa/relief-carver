Relief-Carver: Convert elevation data into G-code
=============

Simple and slow, just using Ruby. Generates a big file with lots of
G-code codes.


Installation:
------------

First:

    make sure you have a decent ruby ('ruby --version' should be at
    1.9.3 or higher)

Get Bundler:

    gem install bundler

Let Bundler get the required gems

    bundle install

And finally:

    Edit carver.rb top section and adjust the parameters as needed.

    Generate the data by running `./carver.rb`.

    Bob's your uncle.


Things to do:
------------

Need to implement proper GCode generation function (what was that code
again?).

Use less global variables and write better Ruby code (this code is far
from 'nice').
