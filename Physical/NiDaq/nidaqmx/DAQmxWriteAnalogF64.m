function [status, a, b]=DAQmxWriteAnalogF64(taskHandle, numSampsPerChan, autoStart,...
    timeout, dataLayout, writeArray, sampsPerChanWritten)

[status, a, b] = daq.ni.NIDAQmx.DAQmxWriteAnalogF64(taskHandle, int32(numSampsPerChan),...
    uint32(autoStart),timeout, uint32(dataLayout), writeArray, int32(sampsPerChanWritten), uint32(0));
