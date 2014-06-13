#!/bin/sh

echo 'compile nbody in D:'
time dmd -release -O nbody.d

echo 'compile nbody in java:'
time javac nbody.java

echo 'compile fannkuchredux in D:'
time dmd -release -O fannkuchredux.d

echo 'compile fannkuchredux in java:'
time javac fannkuchredux.java

echo 'compile meteor in D:'
time dmd -release -O meteor.d

echo 'compile meteor in java:'
time javac meteor.java

echo 'compile fasta in D:'
time dmd -release -O fasta.d

echo 'compile fasta in java:'
time javac fasta.java

echo 'compile fastaredux in D:'
time dmd -release -O fastaredux.d

echo 'compile fastaredux in java:'
time javac fastaredux.java

echo 'compile spectralnorm in D:'
time dmd -release -O spectralnorm.d

echo 'compile spectralnorm in java:'
time javac spectralnorm.java

echo 'compile revcomp in java:'
time javac revcomp.java 

echo 'compile mandelbrot in java:'
time javac mandelbrot.java 

echo 'compile binarytrees in java:'
time javac binarytrees.java 

echo 'compile threadring in java:'
time javac threadring.java 

echo 'compile chameneosredux in java:'
time javac chameneosredux.java 

echo 'compile pidigits in java:'
time javac pidigits.java

echo 'compile regexdna in java:'
time javac regexdna.java

echo 'compile knucleotide in java:'
time javac knucleotide.java

