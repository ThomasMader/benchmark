#!/bin/sh

echo 'run fasta in D:'
time ./fasta 250000

echo 'run fasta in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts fasta 250000
