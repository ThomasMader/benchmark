/*
 * The Computer Language Benchmarks Game
 * http://shootout.alioth.debian.org/
 *
 * modified by Mehmet D. AKIN
 * modified by Rikard Mustajärvi
 */

import std.stdio;
import std.exception;
import std.conv;

class fasta {
   static const int IM = 139968;
   static const int IA = 3877;
   static const int IC = 29573;

   static const int LINE_LENGTH = 60;
   static const int BUFFER_SIZE = (LINE_LENGTH + 1)*1024; // add 1 for '\n'

    // Weighted selection from alphabet
    public static string ALU =
              "GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGG"
            ~ "GAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGA"
            ~ "CCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAAT"
            ~ "ACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCA"
            ~ "GCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGG"
            ~ "AGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCC"
            ~ "AGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA";

    public static FloatProbFreq IUB;
    public static FloatProbFreq HOMO_SAPIENS;

    static this() {
	IUB = new FloatProbFreq([
                'a',  'c',  'g',  't',
                'B',  'D',  'H',  'K',
                'M',  'N',  'R',  'S',
                'V',  'W',  'Y'],
		[
                0.27, 0.12, 0.12, 0.27,
                0.02, 0.02, 0.02, 0.02,
                0.02, 0.02, 0.02, 0.02,
                0.02, 0.02, 0.02,
                ]
	);
	HOMO_SAPIENS = new FloatProbFreq(
          [
                'a',
                'c',
                'g',
                't'],
          [
                0.3029549426680,
                0.1979883004921,
                0.1975473066391,
                0.3015094502008]
          );

    }

   static void makeRandomFasta(string id, string desc,
         FloatProbFreq fpf, int nChars)
   {
      const int LINE_LENGTH = fasta.LINE_LENGTH;
      const int BUFFER_SIZE = fasta.BUFFER_SIZE;
      char[] buffer = new char[BUFFER_SIZE];

      if(buffer.length % (LINE_LENGTH + 1) != 0) {
           throw new Exception("buffer size must be a multiple of line length (including line break)"); 
      }

      string descStr = ">" ~ id ~ " " ~ desc ~ '\n';
      write(descStr);

      int bufferIndex = 0;
      while (nChars > 0) {
         int chunkSize;
         if (nChars >= LINE_LENGTH) {
            chunkSize = LINE_LENGTH;
         } else {
            chunkSize = nChars;
         }

         if (bufferIndex == BUFFER_SIZE) {
            write(buffer[0 .. bufferIndex]);
            bufferIndex = 0;
         }

         bufferIndex = fpf
            .selectRandomIntoBuffer(buffer, bufferIndex, chunkSize);
         buffer[bufferIndex++] = '\n';

         nChars -= chunkSize;
      }

      write(buffer[0..bufferIndex]);
   }

    static void makeRepeatFasta(
          string id, string desc, string alu,
          int nChars)
    {
       int aluIndex = 0;

       const int LINE_LENGTH = fasta.LINE_LENGTH;
       const int BUFFER_SIZE = fasta.BUFFER_SIZE;
       char[] buffer = new char[BUFFER_SIZE];

       if(buffer.length % (LINE_LENGTH + 1) != 0) {
           throw new Exception("buffer size must be a multiple of line length (including line break)"); 
       }

        string descStr = ">" ~ id ~ " " ~ desc ~ '\n';
        write(descStr);

        int bufferIndex = 0;
        while (nChars > 0) {
           int chunkSize;
           if (nChars >= LINE_LENGTH) {
              chunkSize = LINE_LENGTH;
         } else {
            chunkSize = nChars;
         }

           if (bufferIndex == BUFFER_SIZE) {
                write(buffer[0..bufferIndex]);
                bufferIndex = 0;
           }

           for (int i = 0; i < chunkSize; i++) {
              if (aluIndex == alu.length) {
                 aluIndex = 0;
              }

              buffer[bufferIndex++] = alu[aluIndex++];
           }
           buffer[bufferIndex++] = '\n';

           nChars -= chunkSize;
        }

       write(buffer[0..bufferIndex]);
    }


    public static class FloatProbFreq {
       static int last = 42;
       char[] chars;
       float[] probs;

       public this(char[] chars, double[] probs) {
          this.chars = chars;
          this.probs = new float[probs.length];
          for (int i = 0; i < probs.length; i++) {
             this.probs[i] = cast(float)probs[i];
          }
          makeCumulative();
       }

       private void makeCumulative() {
            double cp = 0.0;
            for (int i = 0; i < probs.length; i++) {
                cp += probs[i];
                probs[i] = cast(float)cp;
            }
        }

       public int selectRandomIntoBuffer(
             char[] buffer, int bufferIndex, const int nRandom) {
          const char[] chars = this.chars;
          const float[] probs = this.probs;
          const int len = cast(int)probs.length;

          outer:
          for (int rIndex = 0; rIndex < nRandom; rIndex++) {
             const float r = random(1.0f);
                for (int i = 0; i < len; i++) {
                 if (r < probs[i]) {
                    buffer[bufferIndex++] = chars[i];
                    continue outer;
                 }
              }

                buffer[bufferIndex++] = chars[len-1];
          }

            return bufferIndex;
       }

        // pseudo-random number generator
        public static float random(const float max) {
           const float oneOverIM = (1.0f/ IM);
            last = (last * IA + IC) % IM;
            return max * last * oneOverIM;
        }
    }
}

    void main(string[] args)
    {
        int n = 1000;
//        int n = 25000000;
        if (args.length > 1) {
         n = to!int(args[1]);
      }

        fasta.makeRepeatFasta("ONE", "Homo sapiens alu", fasta.ALU, n * 2);
        fasta.makeRandomFasta("TWO", "IUB ambiguity codes", fasta.IUB, n * 3);
        fasta.makeRandomFasta("THREE", "Homo sapiens frequency", fasta.HOMO_SAPIENS, n * 5);
    }

