#!/bin/sh

#echo 'run spectralnorm in D:'
#time ./spectralnorm 5500

echo 'run regexdna in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts regexdna 0 < regexdna-input5000000.txt

