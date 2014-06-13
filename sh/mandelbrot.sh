#!/bin/sh

#echo 'run spectralnorm in D:'
#time ./spectralnorm 5500

echo 'run mandelbrot in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts mandelbrot 16000

