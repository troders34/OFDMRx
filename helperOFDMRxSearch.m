function [camped,toff,foff] = helperOFDMRxSearch(rxIn,sysParam)
%helperOFDMRxSearch Receiver search sequencer.
%   This helper function searches for the synchronization signal of the
%   base station to align the receiver timing to the transmitter timing.
%   Following successful detection of the sync signal, frequency offset
%   estimation is performed to on the first five frames to align the
%   receiver center frequency to the transmitter frequency.
%
%   Once this is completed, the receiver is declared camped and ready for
%   processing data frames. 
%
%   [camped,toff,foff] = helperOFDMRxSearch(rxIn,sysParam)
%   rxIn - input time-domain waveform
%   sysParam - structure of system parameters
%   camped - boolean to indicate receiver has detected sync signal and
%   estimated frequency offset
%   toff - timing offset as calculated from the sync signal location in
%   signal buffer
%   foff - frequency offset as calculated from the first 144 symbols
%   following sync symbol detection
%
% Copyright 2022-2024 The MathWorks, Inc.

persistent syncDetected;
if isempty(syncDetected)
    syncDetected = false;
end

% Create a countdown frame timer to wait for the frequency offset
% estimation algorithm to converge
persistent campedDelay
if isempty(campedDelay)
    % The frequency offset algorithm requires 144 symbols to average before
    % the first valid frequency offset estimate. Wait a minimum number of
    % frames before declaring camped state.
    campedDelay = ceil(144/sysParam.numSymPerFrame); 
end

toff = [];  % by default, return an empty timing offset value to indicate
            % no sync symbol found or searched
camped = false;
foff = 0;

% Form the sync signal
FFTLength = sysParam.FFTLen;
syncPad   = (FFTLength - 62)/2;
syncNulls = [1:syncPad (FFTLength/2)+1 FFTLength-syncPad+2:FFTLength]';
syncSignal = ofdmmod(helperOFDMSyncSignal(),FFTLength,0,syncNulls);

if ~syncDetected
    % Perform timing synchronization
    toff = timingEstimate(rxIn,syncSignal,Threshold = 0.6);

    if ~isempty(toff)
        syncDetected = true;
        toff = toff - sysParam.CPLen;
        fprintf('\nSync symbol found.\n');
        if sysParam.enableCFO
            fprintf('Estimating carrier frequency offset ...');
        else
            camped = true; % go straight to camped if CFO not enabled
            fprintf('Receiver camped.\n');
        end
    else
        syncDetected = false;
        fprintf('.');
    end
else
    % Estimate frequency offset after finding sync symbol
    if campedDelay > 0 && sysParam.enableCFO
        % Run the frequency offset estimator and start the averaging to
        % converge to the final estimate
        foff = helperOFDMFrequencyOffset(rxIn,sysParam);
        fprintf('.');
        campedDelay = campedDelay - 1;
    else
        fprintf('\nReceiver camped.\n');
        camped = true;
    end
end

end
