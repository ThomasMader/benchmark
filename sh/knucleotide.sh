#!/bin/sh

#echo 'run spectralnorm in D:'
#time ./spectralnorm 5500

echo 'run knucleotide in Java:'
time java -Xmx2048m -server -XX:+TieredCompilation -XX:+AggressiveOpts knucleotide 0 < knucleotide-input25000000.txt

