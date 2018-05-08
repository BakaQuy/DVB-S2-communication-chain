%% Projet modulation & coding
% Impact of CFO and CPE on the BER performance
addpath(genpath('Code encodeur'));
addpath(genpath('Code decodeur'));
addpath(genpath('Code mapping-demapping'));
addpath(genpath('Code HRC'));
clear; close all;

%% Parameters
f_cut = 1e+6; % cut off frequency of the nyquist filter [Mhz]
M = 10; % oversampling factor
fsymb = 2*f_cut; % symbol frequency
fsampling = M*fsymb; % sampling frequency
ts = 1/fsampling;
Tsymb = 1/fsymb; % time between two symbols
beta = 0.3; % roll-off factor
Nbps = 4; % number of bits per symbol
modulation = 'qam'; % type of modulation 

Npackets = 1000; % choose such that Nbits/Nbps is an integer
packetLength = 128;
codedWordLength = 2*packetLength;
Nbits = Npackets*packetLength; % bit stream length
NcodedBits = Npackets*codedWordLength; % full coded word length
bits_tx = randi(2,Nbits,1)-1;
bits_tx_coded = zeros(NcodedBits,1);
iter = 5;

fc = 2e+9;
CFO = 0;%fc*1e-6; % in ppm
CFE = 0;

%% LDPC encoder
H0 = makeLdpc(packetLength, codedWordLength, 0, 1, 3);
for k=1:Npackets
    packet_tx = bits_tx(1+(k-1)*packetLength : k*packetLength);
    [codedbits, H] = makeParityChk(packet_tx , H0, 0);
    bits_tx_coded(1+(k-1)*codedWordLength : k*codedWordLength) = [codedbits packet_tx];
end
tannerGraph = buildTannerGraph(H);

%% Mapping of encoded signal
signal_uncoded = mapping(bits_tx,Nbps,modulation);
signal_coded = mapping(bits_tx_coded,Nbps,modulation);

%% Upsampling
signal_tx_uncoded = upsample(signal_uncoded,M);
signal_tx = upsample(signal_coded,M);

%% Implementation of HHRC
RRCtaps = 365;
stepoffset = (1/RRCtaps)*fsampling;
highestfreq = (RRCtaps-1)*stepoffset/2;
f = linspace(-highestfreq,highestfreq,RRCtaps);
Hrc = HRC(f,Tsymb,beta);
h_t = ifft(Hrc);
h_freq = sqrt(fft(h_t/max(h_t)));
h_time = fftshift(ifft(ifftshift(h_freq)));

%% Convolution
signal_hrrc_tx_uncoded = conv(signal_tx_uncoded, h_time);
signal_hrrc_tx = conv(signal_tx, h_time);

%% Noise through the channel uncoded
EbN0 = -5:16;
BER = zeros(length(EbN0),1);

signal_power_uncoded = (trapz(abs(signal_hrrc_tx_uncoded).^2))*(1/fsampling); % total power
Eb = signal_power_uncoded*0.5/(Npackets*packetLength); % energy per bit

t = 0:length(signal_hrrc_tx_uncoded)-1;
t = (t-(RRCtaps-1)/2)*ts;
exp_cfo = exp(1j*(2*pi*CFO*t+CFE))';

for j = 1:length(EbN0)
    N0 = Eb/10.^(EbN0(j)/10);
    NoisePower = 2*N0*fsampling;
    noise = sqrt(NoisePower/2)*(randn(length(signal_hrrc_tx_uncoded),1)+1i*randn(length(signal_hrrc_tx_uncoded),1));

    signal_rx = signal_hrrc_tx_uncoded + noise;
    signal_rx_cfo_cfe = signal_rx.*exp_cfo;
    signal_hhrc_rx = conv(signal_rx_cfo_cfe, h_time);
    signal_hhrc_rx_trunc = signal_hhrc_rx(RRCtaps:end-RRCtaps+1);

    %% Downsampling
    signal_rx_down = real(downsample(signal_hhrc_rx_trunc, M));

    %% Demapping
    uncoded_bits_rx = (demapping(signal_rx_down,Nbps,modulation))';
    BER(j,1) = length(find(bits_tx ~= uncoded_bits_rx'))/length(uncoded_bits_rx');
end

%% Noise through the channel coded
% signal_power = (trapz(abs(signal_hrrc_tx).^2))*(1/fsampling); % total power
% Eb = signal_power*0.5/(Npackets*codedWordLength); % energy per bit
% for j = 1:length(EbN0)
%     N0 = Eb/10.^(EbN0(j)/10);
%     NoisePower = 2*N0*fsampling;
%     noise = sqrt(NoisePower/2)*(randn(length(signal_hrrc_tx),1)+1i*randn(length(signal_hrrc_tx),1));
% 
%     signal_rx = signal_hrrc_tx + noise;
%     signal_hhrc_rx = conv(signal_rx, h_time);
%     signal_hhrc_rx_trunc = signal_hhrc_rx(RRCtaps:end-RRCtaps+1);
% 
%     %% Downsampling
%     signal_rx_down = real(downsample(signal_hhrc_rx_trunc, M));
% 
%     %% Demapping
%     encoded_bits_rx = (demapping(signal_rx_down,Nbps,modulation))';
% 
%     %% Hard Decoding
%     decoded_bits_rx = zeros(Nbits,1);
%     for k=1:Npackets
%         packet_rx = encoded_bits_rx(1+(k-1)*codedWordLength : k*codedWordLength);
%         decoded_packet_rx = LdpcHardDecoder(packet_rx, H, tannerGraph, iter);
%         decoded_bits_rx(1+(k-1)*packetLength:k*packetLength) = decoded_packet_rx(packetLength+1:end);
%     end
%     BER(j) = length(find(bits_tx ~= decoded_bits_rx))/length(decoded_bits_rx);
% end

%% Plot BER results
semilogy(EbN0,BER(:));
xlabel('E_B/N_0 [dB]');
ylabel('BER');
legend('Uncoded');
title('Hard Decoding BPSK')
grid on;