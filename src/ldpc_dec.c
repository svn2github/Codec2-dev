/* 
  FILE...: ldpc_dec.c
  AUTHOR.: Matthew C. Valenti, Rohit Iyer Seshadri, David Rowe
  CREATED: Sep 2016

  Command line C LDPC decoder derived from MpDecode.c in the CML
  library.  Allows us to run the same decoder in Octave and C.  The
  code is defined by the parameters and array stored in the include
  file below, which can be machine generated from the Octave function
  ldpc_fsk_lib.m:ldpc_decode()

  The include file also contains test input/output vectors for the LDPC
  decoder for testing this program.

  Build:

    $ gcc -o ldpc_dec ldpc_dec.c mpdecode_core.c -Wall -lm -g

  TODO:
  [ ] C cmd line encoder
      [ ] SD output option
      [ ] Es/No option for testing
  [ ] decoder
      [X] test mode or file I/O (incl stdin/stdout)
      [X] Octave code to generate include file
          + MAX_ITER as well
      [ ] check into SVN
      [ ] enc/dec running on cmd line
      [ ] fsk_demod modified for soft decisions
      [ ] drs232 modified for SD
          + use UW syn cin this program to check BER with coding
      [ ] revisit CML support, maybe blog post
*/

#include <assert.h>
#include <errno.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "mpdecode_core.h"

/* Machine generated consts, H_rows, H_cols, test input/output data to
   change LDPC code regenerate this file. */

#include "ldpc_code.h"  

void run_ldpc_decoder(int DecodedBits[], int ParityCheckCount[], double input[]);

int main(int argc, char *argv[])
{    
    int         CodeLength, NumberParityBits, max_iter;
    int         i, j, r, num_ok, num_runs;
    
    /* derive some parameters */

    max_iter   = MAX_ITER;
    CodeLength = CODELENGTH;                    /* length of entire codeword */
    NumberParityBits = NUMBERPARITYBITS;
	
    if (argc < 2) {
        fprintf(stderr, "usage: %s --test\n", argv[0]);
        fprintf(stderr, "usage: %s InOneSDSymbolPerDouble OutOneBitPerInt\n", argv[0]);
        exit(0);
    }

    int *DecodedBits = calloc( max_iter*CodeLength, sizeof( int ) );
    int *ParityCheckCount = calloc( max_iter, sizeof(int) );

    if (!strcmp(argv[1],"--test")) {

        /* test mode --------------------------------------------------------*/

        fprintf(stderr, "Starting test using pre-compiled test data .....\n");
        fprintf(stderr, "Codeword length: %d\n",  CodeLength);
        fprintf(stderr, "Parity Bits....: %d\n",  NumberParityBits);

        num_runs = 100; num_ok = 0;

        for(r=0; r<num_runs; r++) {

            run_ldpc_decoder(DecodedBits, ParityCheckCount, input);

            /* Check output. Bill has modified decoded to write number of parity checks that are correct
               to the BitErrors array.  So if decoding is correct the final BitErrors entry will have 
               NumberParityBits */

            /* find output bit row where decoding has finished */

            int ok = 0;
            for (i=0;i<max_iter;i++) {
                if (ParityCheckCount[i] == NumberParityBits) {
                    for (j=0;j<CodeLength;j++) {
                        if (output[i + j*max_iter] == DecodedBits[i+j*max_iter])                    
                            ok++;
                    }
                }
            }
            if (ok == CodeLength)
                num_ok++;            
        }

        fprintf(stderr, "test runs......: %d\n",  num_runs);
        fprintf(stderr, "test runs OK...: %d\n",  num_ok);
        if (num_runs == num_ok)
            fprintf(stderr, "test runs OK...: PASS\n");
        else
            fprintf(stderr, "test runs OK...: FAIL\n");
    }
    else {
        FILE *fin, *fout;

        /* File I/O mode ------------------------------------------------*/

        if (strcmp(argv[1], "-")  == 0) fin = stdin;
        else if ( (fin = fopen(argv[1],"rb")) == NULL ) {
            fprintf(stderr, "Error opening input SD file: %s: %s.\n",
                    argv[2], strerror(errno));
            exit(1);
        }
        
        if (strcmp(argv[2], "-") == 0) fout = stdout;
        else if ( (fout = fopen(argv[2],"wb")) == NULL ) {
            fprintf(stderr, "Error opening output bit file: %s: %s.\n",
                    argv[3], strerror(errno));
            exit(1);
        }

        double *input_double  =  calloc(CodeLength, sizeof(double));

        while(fread(input_double, sizeof(double), CodeLength, fin) == 1) {
            run_ldpc_decoder(DecodedBits, ParityCheckCount, input_double);
            fwrite(DecodedBits, sizeof(int), CodeLength, fout);
        }

        free(input_double);
    }

    /* Clean up memory */

    free(ParityCheckCount);
    free(DecodedBits);

    return 0;
}


void run_ldpc_decoder(int DecodedBits[], int ParityCheckCount[], double input[]) {
    int		max_iter, dec_type;
    float       q_scale_factor, r_scale_factor;
    int		max_row_weight, max_col_weight;
    int         CodeLength, NumberParityBits, NumberRowsHcols, shift, H1;
    int         i;
    struct c_node *c_nodes;
    struct v_node *v_nodes;
    
    /* default values */

    max_iter  = MAX_ITER;
    dec_type  = 0;
    q_scale_factor = 1;
    r_scale_factor = 1;

    /* derive some parameters */

    CodeLength = CODELENGTH;                    /* length of entire codeword */
    NumberParityBits = NUMBERPARITYBITS;
    NumberRowsHcols = NUMBERROWSHCOLS;

    shift = (NumberParityBits + NumberRowsHcols) - CodeLength;
    if (NumberRowsHcols == CodeLength) {
        H1=0;
        shift=0;
    } else {
        H1=1;
    }
	
    max_row_weight = MAX_ROW_WEIGHT;
    max_col_weight = MAX_COL_WEIGHT;
	
#ifdef TT
    /* check H_rows[] */

    int length;
    int gd = 0, bd = 0;
    length = NumberRowsHcols*max_col_weight;
    for (i=0;i<length;i++) {
        if (H_cols[i] == H_cols2[i])
            gd++;
        else {
            bd++;
            printf("%d H_cols: %f H_cols2: %f\n", i, H_cols[i], H_cols2[i]);
        }
        if (bd == 10)
            exit(0);
    }
    printf("gd: %d bd: %d\n", gd, bd);
#endif

    c_nodes = calloc( NumberParityBits, sizeof( struct c_node ) );
    v_nodes = calloc( CodeLength, sizeof( struct v_node));
	
    /* initialize c-node and v-node structures */

    c_nodes = calloc( NumberParityBits, sizeof( struct c_node ) );
    v_nodes = calloc( CodeLength, sizeof( struct v_node));
	
    init_c_v_nodes(c_nodes, shift, NumberParityBits, max_row_weight, H_rows, H1, CodeLength, 
                   v_nodes, NumberRowsHcols, H_cols, max_col_weight, dec_type, input);

    int DataLength = CodeLength - NumberParityBits;
    int *data_int = calloc( DataLength, sizeof(int) );
	
    /* Call function to do the actual decoding */

    if ( dec_type == 1) {
        MinSum( ParityCheckCount, DecodedBits, c_nodes, v_nodes, CodeLength, 
                NumberParityBits, max_iter, r_scale_factor, q_scale_factor, data_int );
    } else if ( dec_type == 2) {
        fprintf(stderr, "dec_type = 2 not currently supported");
        /* ApproximateMinStar( BitErrors, DecodedBits, c_nodes, v_nodes, 
           CodeLength, NumberParityBits, max_iter, r_scale_factor, q_scale_factor );*/
    } else {
        SumProduct( ParityCheckCount, DecodedBits, c_nodes, v_nodes, CodeLength, 
                    NumberParityBits, max_iter, r_scale_factor, q_scale_factor, data_int ); 
    }

    /* Clean up memory */

    free( data_int );

    /*  Cleaning c-node elements */

    for (i=0;i<NumberParityBits;i++) {
        free( c_nodes[i].index );
        free( c_nodes[i].message );
        free( c_nodes[i].socket );
    }
	
    /* printf( "Cleaning c-nodes \n" ); */
    free( c_nodes );
	
    /* printf( "Cleaning v-node elements\n" ); */
    for (i=0;i<CodeLength;i++) {
        free( v_nodes[i].index);
        free( v_nodes[i].sign );
        free( v_nodes[i].message );
        free( v_nodes[i].socket );
    }
	
    /* printf( "Cleaning v-nodes \n" ); */
    free( v_nodes );
}