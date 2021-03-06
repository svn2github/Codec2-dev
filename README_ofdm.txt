
README_ofdm.txt
David Rowe
Created Mar 2018

Introduction
------------

A 1600 bit/s (nominal uncoded payload data rate) Orthogonal Frequency
Division Multiplexed (OFDM) modem.  Used for digital voice over HF
SSB.  Designed to be used with a rate 0.5 LDPC code with 700 bit/s
coded voice.

The OFDM modem was first implemented in GNU Octave, then ported to C.
Algorithm development is generally easier in Octave, but for real time
work we need the C version.  Automated units tests ensure the
operation of the Octave and C versions are identical.

Refs
-----

[1] Spreadsheet (OFDM tab) describing the waveform design,
    https://svn.code.sf.net/p/freetel/code/codec2-dev/octave/cohpsk_frame_design.ods

[2] Towards FreeDV 700D, https://www.rowetel.com/?p=5573

[3] FreeDV 700D - First Over The Air Tests, https://www.rowetel.com/?p=5630

[4] Steve Ports an OFDM modem from Octave to C, https://www.rowetel.com/?p=5824

Quickstart
----------

Built as part of codec2-dev, see README for build instructions.

1. Generate 10 seconds of test frame bits, modulate, and play audio
   out of sound device:

    build_linux/src$ ./ofdm_get_test_bits - 10 | ./ofdm_mod - - | play -t raw -r 8000 -s -2 -

2. Generate 10 seconds of test frame bits, modulate, and play audio:

    build_linux/src$ ./ofdm_get_test_bits - 10 | ./ofdm_mod - - | ./ofdm_demod - - | ./ofdm_put_test_bits -

    (TODO write ofdm_demod_c.m)
    Use Octave to look at plots of C modem operation:

    $ cd ../octave
    $ octave
    octave:1> ofdm_demod_c("../src/demod_dump.txt")

4. Run Octave versions of mod and demod (called tx and rx to avoid
   namespace clashes in Octave):

     $ cd ~/octave
     $ octave --no-gui
     octave:1> ofdm_tx("ofdm_test.raw",10)
     octave:1> ofdm_rx("ofdm_test.raw")

   The Octave modulator ofdm_tx can simulate channel impairments, for
   example AWGN noise at an Eb/No of 4dB:

     octave:1> ofdm_tx("ofdm_test.raw",10, 4)

   The Octave versions use the same test frames as C so can interoperate.

     build_linux/src$ ./ofdm_demod ../../octave/ofdm_test.raw - | ./ofdm_put_test_bits -
     
Acceptance Tests
----------------

The rate 1/2 LPDC code can correct up to about 10% raw BER, so a good
test is to run the modem at Eb/No operating points that produce just
less that BER=0.1

The BER2 measure truncates the effect of any start up transients,
e.g. as the frequency offset is tracked out.

1/ HF Multipath:

  octave:580> ofdm_tx("ofdm_test.raw",60,4,'hf',20,-0.1)
  octave:581> ofdm_rx("ofdm_test.raw")
  BER2.: 0.0997 Tbits: 93752 Terrs:  9344

2/ AWGN:

  octave:582> ofdm_tx("ofdm_test.raw",60,0,'awgn')
  octave:583> ofdm_rx("ofdm_test.raw")
  BER2.: 0.0827 Tbits: 96846 Terrs:  8008

C Code
------

ofdm.c             - OFDM library
codec2_ofdm.h      - API header file for OFDM library 
ofdm_get_test_bits - generate OFDM test frames
ofdm_mod           - OFDM modulator command line program
ofdm_demod         - OFDM demodulator command line program
ofdm_put_test_bits - measure BER in OFDM test frames
unittest/tofdm     - Run C port of modem to compare with octave version (see octave/tofdm)

Octave Scripts
--------------

ofdm_lib - OFDM library 
ofdm_dev - used for modem development, run various simulations
ofdm_tx  - modulate test frames to a file of sample, cam add channel impairments
ofdm_rx  - demod from a sample file and count errors
tofdm    - Compares Octave and C ports of modem

Specifications (Nominal FreeDV 700D configuration)
--------------------------------------------------

Modem.........: OFDM, pilot assisted coherent QPSK
Payload bits/s: 700
Text bits/s...: 25
Unique Word...: 10 bits
Carriers......: 17
RF bandwidth..: 944 Hz
Symbol period.: 18ms
Cyclic Prefix.: 2ms (note 1)
Pilot rate....: 1 in every 8 symbols
Frame Period..: 160ms
FEC...........: rate 1/2 (224,112) LDPC
Operating point
  AWGN........: Eb/No -0.5dB SNR(3000Hz): -2.5dB (note 2)
  HF Multipath: Eb/No  4.0dB SNR(3000Hz):  2.0dB (note 3)
  
Freq offset.......: +/- 20  Hz   (sync range)
Freq drift........: +/- 0.2 Hz/s (for 0.5 dB loss)
Sample clock error: 1000 ppm

Notes:
  1/ Modem can cope with 2ms of multipath
  2/ Ideal SNR(3000) = Eb/No + 10*log10(Rb/B)
                     = -1 + 10*log10(1400/3000)
                     = -4.3 dB,
     So we have about 1.8dB overhead for synchronisation, implementation loss,
     and the text channel.
  3/ HF Multipath channel used for testing is two path, 1Hz Doppler, 1ms delay
