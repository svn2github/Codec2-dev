% ofdm_dev.m
% David Rowe April 2017
%
% Simulations used for development and testing of Rate Fs BPSK/QPSK
% OFDM modem.

ofdm_lib;

#{
  TODO: 
    [ ] compute SNR and PAPR
    [ ] SSB bandpass filtering
    [ ] way to simulate aquisition and demod
    [ ] testframe based 
#}

function [sim_out rate_fs_pilot_samples rx] = run_sim(sim_in)

  % set up core modem constants

  states = ofdm_init(sim_in.bps, sim_in.Rs, sim_in.Tcp, sim_in.Ns, sim_in.Nc);
  ofdm_load_const;
  
  % simulation parameters and flags

  woffset = 2*pi*sim_in.foff_hz/Fs;
  EbNodB  = sim_in.EbNodB;
  verbose = states.verbose = sim_in.verbose;
  hf_en   = sim_in.hf_en;
  timing_en = states.timing_en = sim_in.timing_en;
  states.foff_est_en = foff_est_en = sim_in.foff_est_en;
  states.phase_est_en = phase_est_en = sim_in.phase_est_en;

  if verbose
    printf("Rs:..........: %4.2f\n", Rs);
    printf("M:...........: %d\n", M);
    printf("Ncp:.........: %d\n", Ncp);
    printf("bps:.........: %d\n", bps);
    printf("Nbitsperframe: %d\n", Nbitsperframe);
    printf("Nrowsperframe: %d\n", Nrowsperframe);
    printf("Nsamperframe.: %d\n", Nsamperframe);
  end

  % Important to define run time in seconds so HF model will evolve the same way
  % for different pilot insertion rates.  So lets work backwards from approx
  % seconds in run to get Nbits, the total number of payload data bits

  Nrows = sim_in.Nsec*Rs;
  Nframes = floor((Nrows-1)/Ns);
  Nbits = Nframes * Nbitsperframe;    % number of payload data bits

  Nr = Nbits/(Nc*bps);                % Number of data rows to get Nbits total

  % double check if Nbits fit neatly into carriers

  assert(Nbits/(Nc*bps) == floor(Nbits/(Nc*bps)), "Nbits/(Nc*bps) must be an integer");

  Nrp = Nr + Nframes + 1;  % number of rows once pilots inserted
                           % extra row of pilots at end

  if verbose
    printf("Nc.....: %d\n", Nc);
    printf("Ns.....: %d (step size for pilots, Ns-1 data symbols between pilots)\n", Ns);
    printf("Nr.....: %d\n", Nr);
    printf("Nbits..: %d\n", Nbits);
    printf("Nframes: %d\n", Nframes);
    printf("Nrp....: %d (number of rows including pilots)\n", Nrp);
  end

  % set up HF model ---------------------------------------------------------------

  if hf_en

    % some typical values, or replace with user supplied

    dopplerSpreadHz = 1.0; path_delay_ms = 1;

    if isfield(sim_in, "dopplerSpreadHz") 
      dopplerSpreadHz = sim_in.dopplerSpreadHz;
    end
    if isfield(sim_in, "path_delay_ms") 
      path_delay_ms = sim_in.path_delay_ms;
    end
    path_delay_samples = path_delay_ms*Fs/1000;
    printf("Doppler Spread: %3.2f Hz Path Delay: %3.2f ms %d samples\n", dopplerSpreadHz, path_delay_ms, path_delay_samples);

    % generate same fading pattern for every run

    randn('seed',1);

    spread1 = doppler_spread(dopplerSpreadHz, Fs, (sim_in.Nsec*(M+Ncp)/M+0.2)*Fs);
    spread2 = doppler_spread(dopplerSpreadHz, Fs, (sim_in.Nsec*(M+Ncp)/M+0.2)*Fs);

    % sometimes doppler_spread() doesn't return exactly the number of samples we need
 
    assert(length(spread1) >= Nrp*M, "not enough doppler spreading samples");
    assert(length(spread2) >= Nrp*M, "not enough doppler spreading samples");

    hf_gain = 1.0/sqrt(var(spread1)+var(spread2));
    % printf("nsymb: %d lspread1: %d\n", nsymb, length(spread1));
  end
 
  % ------------------------------------------------------------------
  % simulate for each Eb/No point 
  % ------------------------------------------------------------------

  for nn=1:length(EbNodB)
    rand('seed',1);
    randn('seed',1);

    EbNo = bps * (10 .^ (EbNodB(nn)/10));
    variance = 1/(M*EbNo/2);

    Nsam = Nrp*(M+Ncp);

    % generate tx bits and run OFDM modulator

    tx_bits = rand(1,Nbits) > 0.5;

    tx = [];
    for f=1:Nframes
      tx = [tx ofdm_mod(states, tx_bits((f-1)*Nbitsperframe+1:f*Nbitsperframe))];
    end

    % add extra row of pilots at end, to allow one frame simulations,
    % useful for development

    st = Nsamperframe*(Nframes-1)+1; en = st+Ncp+M-1;
    tx = [tx tx(st:en)];
    assert(length(tx) == Nsam);

    % channel simulation ---------------------------------------------------------------
    
    if isfield(sim_in, "sample_clock_offset_ppm") 
      % todo: this only works for large ppm like 500, runs out of memory
      %       for small ppm

      if sim_in.sample_clock_offset_ppm
        timebase = floor(abs(1E6/sim_in.sample_clock_offset_ppm));
        if sim_in.sample_clock_offset_ppm > 0
          tx = resample(tx, timebase+1, timebase);
        else
          tx = resample(tx, timebase, timebase+1);
        end

        % make sure length is correct for rest of simulation

        tx = [tx zeros(1,Nsam-length(tx))];
        tx = tx(1:Nsam);
      end
    end

    rx = tx;

    if hf_en
      %rx  =  [zeros(1,path_delay_samples) tx(1:Nsam-path_delay_samples)];
      rx  = hf_gain * tx(1:Nsam) .* spread1(1:Nsam);
      rx  += hf_gain * [zeros(1,path_delay_samples) tx(1:Nsam-path_delay_samples)] .* spread2(1:Nsam);
    end

    rx = rx .* exp(j*woffset*(1:Nsam));

    noise = sqrt(variance)*(0.5*randn(1,Nsam) + j*0.5*randn(1,Nsam));
    rx += noise;

    % some spare samples at end to avoid overflow as est windows may poke into the future a bit

    rx = [rx zeros(1,Nsamperframe)];
    
    % bunch of logs

    phase_est_pilot_log = [];
    delta_t_log = []; 
    timing_est_log = [];
    foff_est_hz_log = [];
    Nerrs_log = [];
    rx_bits = []; rx_np = [];

    % reset some states for each EbNo simulation point

    states.sample_point = states.timing_est = 1;
    if timing_en == 0
      states.sample_point = Ncp;
    end
    states.nin = Nsamperframe;
    states.foff_est_hz = 0;    

    % for this simulation we "prime" buffer to allow one frame runs during development

    prx = 1;
    states.rxbuf(M+Ncp+2*Nsamperframe+1:Nrxbuf) = rx(prx:Nsamperframe+2*(M+Ncp));
    prx += Nsamperframe+2*(M+Ncp);

    for f=1:Nframes

      % insert samples at end of buffer, set to zero if no samples
      % available to disable phase estimation on future pilots on last
      % frame of simulation

      lnew = min(Nsam-prx,states.nin);
      rxbuf_in = zeros(1,states.nin);

      if lnew
        rxbuf_in(1:lnew) = rx(prx:prx+lnew-1);
      end
      prx += states.nin;

      [arx_bits states aphase_est_pilot_log arx_np] = ofdm_demod(states, rxbuf_in);

      rx_bits = [rx_bits arx_bits]; rx_np = [rx_np arx_np];
      timing_est_log = [timing_est_log states.timing_est];
      delta_t_log = [delta_t_log states.delta_t];
      foff_est_hz_log = [foff_est_hz_log states.foff_est_hz];
      phase_est_pilot_log = [phase_est_pilot_log; aphase_est_pilot_log];
    end

    assert(length(rx_bits) == Nbits);

    % calculate BER stats as a block, after pilots extracted

    errors = xor(tx_bits, rx_bits);
    Nerrs = sum(errors);
    for f=1:Nframes
      st = (f-1)*Nbitsperframe+1; en = st + Nbitsperframe-1;
      Nerrs_log(f) = sum(xor(tx_bits(st:en), rx_bits(st:en)));
    end

    printf("EbNodB: %3.2f BER: %5.4f Nbits: %d Nerrs: %d\n", EbNodB(nn), Nerrs/Nbits, Nbits, Nerrs);

    if verbose

      figure(1); clf; 
      plot(rx_np,'+');
      %axis([-2 2 -2 2]);
      title('Scatter');
      
      figure(2); clf;
      plot(phase_est_pilot_log(:,2:Nc+1),'g+', 'markersize', 5); 
      title('Phase est');
      axis([1 Nrp -pi pi]);  

      figure(3); clf;
      subplot(211)
      stem(delta_t_log)
      title('delta t');
      subplot(212)
      plot(timing_est_log);
      title('timing est');

      figure(4); clf;
      plot(foff_est_hz_log)
      axis([1 max(Nframes,2) -3 3]);
      title('Fine Freq');

      figure(5); clf;
      plot(Nerrs_log);


      figure(6)
      Tx = abs(fft(tx(1:Nsam).*hanning(Nsam)'));
      Tx_dB = 20*log10(Tx);
      dF = Fs/Nsam;
      plot((1:Nsam)*dF, Tx_dB);
      mx = max(Tx_dB);
      axis([0 Fs/2 mx-60 mx])

     
#{
      if hf_en
        figure(4); clf; 
        subplot(211)
        plot(abs(spread1(1:Nsam)));
        %hold on; plot(abs(spread2(1:Nsam)),'g'); hold off;
        subplot(212)
        plot(angle(spread1(1:Nsam)));
        title('spread1 amp and phase');
      end
#}
      
#{
      % todo, work out a way to plot rate Fs hf model phase
      if sim_in.hf_en
        plot(angle(hf_model(:,2:Nc+1)));
      end
#}


    end

    sim_out.ber(nn) = sum(Nerrs)/Nbits; 
    sim_out.pilot_overhead = 10*log10(Ns/(Ns-1));
    sim_out.M = M; sim_out.Fs = Fs; sim_out.Ncp = Ncp;
    sim_out.Nrowsperframe = Nrowsperframe; sim_out.Nsamperframe = Nsamperframe;
  end
endfunction


function run_single
  Ts = 0.018; 
  sim_in.Tcp = 0.002; 
  sim_in.Rs = 1/Ts; sim_in.bps = 2; sim_in.Nc = 16; sim_in.Ns = 8;

  sim_in.Nsec = 5*(sim_in.Ns+1)/sim_in.Rs;  % one frame
  %sim_in.Nsec = 30;

  sim_in.EbNodB = 10;
  sim_in.verbose = 1;
  sim_in.hf_en = 0;
  sim_in.foff_hz = 0;
  sim_in.sample_clock_offset_ppm = 0;

  sim_in.timing_en = 1;
  sim_in.foff_est_en = 1;
  sim_in.phase_est_en = 1;

  run_sim(sim_in);
end


% Plot BER against Eb/No curves for AWGN and HF

% Target operating point Eb/No for HF is 6dB, as this is where our rate 1/2
% LDPC code gives good results (10% PER, 1% BER).  However this means
% the Eb/No at the input is 10*log(1/2) or 3dB less, so we need to
% make sure phase est works at Eb/No = 6 - 3 = 3dB
%
% For AWGN target is 2dB so -1dB op point.

function run_curves
  Ts = 0.010;
  sim_in.Rs = 1/Ts;
  sim_in.Tcp = 0.002; 
  sim_in.bps = 2; sim_in.Ns = 8; sim_in.Nc = 8; sim_in.verbose = 0;
  sim_in.foff_hz = 0;

  pilot_overhead = (sim_in.Ns-1)/sim_in.Ns;
  cp_overhead = Ts/(Ts+sim_in.Tcp);
  overhead_dB = -10*log10(pilot_overhead*cp_overhead);

  sim_in.hf_en = 0;
  sim_in.Nsec = 30;
  sim_in.EbNodB = -3:5;
  awgn_EbNodB = sim_in.EbNodB;

  awgn_theory = 0.5*erfc(sqrt(10.^(sim_in.EbNodB/10)));
  awgn = run_sim(sim_in);

  sim_in.hf_en = 1;
  sim_in.Nsec = 120;
  sim_in.EbNodB = 1:8;

  EbNoLin = 10.^(sim_in.EbNodB/10);
  hf_theory = 0.5.*(1-sqrt(EbNoLin./(EbNoLin+1)));

  hf = run_sim(sim_in);

  figure(4); clf;
  semilogy(awgn_EbNodB, awgn_theory,'b+-;AWGN theory;');
  hold on;
  semilogy(sim_in.EbNodB, hf_theory,'b+-;HF theory;');
  semilogy(awgn_EbNodB+overhead_dB, awgn_theory,'g+-;AWGN lower bound with pilot + CP overhead;');
  semilogy(sim_in.EbNodB+overhead_dB, hf_theory,'g+-;HF lower bound with pilot + CP overhead;');
  semilogy(awgn_EbNodB+overhead_dB, awgn.ber,'r+-;AWGN sim;');
  semilogy(sim_in.EbNodB+overhead_dB, hf.ber,'r+-;HF sim;');
  hold off;
  axis([-3 8 1E-2 2E-1])
  xlabel('Eb/No (dB)');
  ylabel('BER');
  grid; grid minor on;
  legend('boxoff');
end


% Run an acquisition test, returning vectors of estimation errors

function [delta_t delta_foff] = acquisition_test(Ntests=10, EbNodB=100, foff_hz=0, hf_en=0, fine_en=0)

  % generate test signal at a given Eb/No and frequency offset

  Ts = 0.016; 
  sim_in.Tcp = 0.002; 
  sim_in.Rs = 1/Ts; sim_in.bps = 2; sim_in.Nc = 16; sim_in.Ns = 8;

  sim_in.Nsec = Ntests*(sim_in.Ns+1)/sim_in.Rs;

  sim_in.EbNodB = EbNodB;
  sim_in.verbose = 0;
  sim_in.hf_en = hf_en;
  sim_in.foff_hz = foff_hz; sim_in.timing_en = 0;

  % set up acquistion 

  Nsamperframe = states.Nsamperframe = sim_out.Nsamperframe;
  states.M = sim_out.M; states.Ncp = sim_out.Ncp;
  states.verbose = 0;
  states.Fs = sim_out.Fs;

  % test fine or acquisition over test signal
  #{
    fine: - start with coarse timing instant
          - on each frame est timing a few samples about that point
          - update timing instant

    corr: - where is best plcase to sample
          - just before end of symbol?
          - how long should sequence be?
          - add extra?
          - aim for last possible moment?
          - man I hope IL isn't too big.....
  #}

  delta_t = []; delta_t = [];  delta_foff = [];

  if fine_en

    window_width = 5;                   % search +/-2 samples from current timing instant
    timing_instant = Nsamperframe+1;    % start at correct instant for AWGN
                                        % start at second frame so we can search -2 ... +2

    while timing_instant < (length(rx) - (Nsamperframe + length(rate_fs_pilot_samples) + window_width))
      st = timing_instant - ceil(window_width/2); 
      en = st + Nsamperframe-1 + length(rate_fs_pilot_samples) + window_width-1;
      [ft_est foff_est] = coarse_sync(states, rx(st:en), rate_fs_pilot_samples);
      printf("ft_est: %d timing_instant %d %d\n", ft_est, timing_instant, mod(timing_instant, Nsamperframe));
      timing_instant += Nsamperframe + ft_est - ceil(window_width/2);
      delta_t = [delta_ft ft_est - ceil(window_width/2)];
    end
  else
    % for coarse simulation we just use contant window shifts

    st = 0.5*Nsamperframe; 
    en = 2.5*Nsamperframe - 1;
    ct_target = Nsamperframe/2;

    for w=1:Nsamperframe:length(rx)-3*Nsamperframe
      %st = w+0.5*Nsamperframe; en = st+2*Nsamperframe-1;
      %[ct_est foff_est] = coarse_sync(states, rx(st:en), rate_fs_pilot_samples);
      [ct_est foff_est] = coarse_sync(states, rx(w+st:w+en), rate_fs_pilot_samples);
      printf("ct_est: %4d foff_est: %3.1f\n", ct_est, foff_est);

      % valid coarse timing ests are modulo Nsamperframe

      delta_t = [delta_ct ct_est-ct_target];
      delta_foff = [delta_foff (foff_est-foff_hz)];
    end
  end

endfunction


% Run some tests for various acquisition conditions. Probability of
% acquistion is what matters, e.g. if it's 50% we can expect sync
% within 2 frames
%                 P(t)/P(f)  P(t)/P(f)
%          Eb/No  AWGN       HF
% +/- 25Hz -1/3   1.0/0.3    0.96/0.3 
% +/-  5Hz -1/3   1.0/0.347  0.96/0.55 
% +/- 25Hz  10/10 1.00/0.92  0.99/0.77

function acquisition_histograms(fine_en = 0)
  Fs = 8000;
  Ntests = 100;

  % allowable tolerance for acquistion

  ftol_hz = 2.0;
  ttol_samples = 0.002*Fs;

  % AWGN channel operating point

  [dct dfoff] = acquisition_test(Ntests, -1, 25, 0, fine_en);

  % Probability of acquistion is what matters, e.g. if it's 50% we can
  % expect sync within 2 frames

  printf("AWGN P(time offset acq) = %3.2f\n", length(find (abs(dct) < ttol_samples))/length(dct));
  if fine_en == 0
    printf("AWGN P(freq offset acq) = %3.2f\n", length(find (abs(dfoff) < ftol_hz))/length(dfoff));
  end

  figure(1)
  hist(dct(find (abs(dct) < ttol_samples)))
  if fine_en == 0
    figure(2)
    hist(dfoff)
  end

  % HF channel operating point

  [dct dfoff] = acquisition_test(Ntests, 3, 25, 1, fine_en);

  printf("HF P(time offset acq) = %3.2f\n", length(find (abs(dct) < ttol_samples))/length(dct));
  if fine_en == 0
    printf("HF P(freq offset acq) = %3.2f\n", length(find (abs(dfoff) < ftol_hz))/length(dfoff));
  end

  figure(3)
  hist(dct(find (abs(dct) < ttol_samples)))
  if fine_en == 0
    figure(4)
    hist(dfoff)
  end

endfunction


% ---------------------------------------------------------
% choose simulation to run here 
% ---------------------------------------------------------

format;
more off;

run_single
%run_curves
%acquisition_histograms(1)
