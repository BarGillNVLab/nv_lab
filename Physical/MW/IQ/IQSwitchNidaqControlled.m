classdef IQSwitchNidaqControlled < handle
    % Wrapper for I2 and Q2 channels, using niDaq and I/Q switches
    
    properties (Constant)
        NEEDED_FIELDS = {'I2', 'Q2'}
        
        MAX_AMPLITUDE = 0.5;    % in volts
        ANGLE_SHIFT = -135;     % use to tile to the regular IQ frame
    end
    
    properties        
       amplitudeScale %from -1 to 1 relative to the maximal amplitude       
       angle 
    end
    
    properties (Access = private)        
       I
       Q
    end
    
    methods
        % Constructor
        function obj = IQSwitchNidaqControlled(I2Address, Q2Address)
            % Create a struct for each NiDaq channel, and register it in
            % the Daq.
            
            % I2 channel
            S = struct('channel', I2Address, 'minVal', -obj.MAX_AMPLITUDE, 'maxVal', obj.MAX_AMPLITUDE);
            obj.I = NiDaqControlledAnalogChannel.create('I2 voltage', S);
            
            % Q2 channel (almost identical)
            S.channel = Q2Address;
            obj.Q = NiDaqControlledAnalogChannel.create('Q2 voltage', S);
            
            % Initialize values
            obj.amplitudeScale = 0;
            obj.angle = 0;
        end
    end    
    methods
        function scalePower(obj, newAmplitudeScale, newAngle) 
            % Change the power using the amplitudeScale and angle, with
            % respect to the maximal allowed output.
            % If newAmplitudeScale & newAngle are given - amplitudeScale
            % and angle will be updated in obj. Otherwise, the values from
            % amplitudeScale and angle will be used.
            if nargin > 1
                obj.angle = newAngle;
                obj.amplitudeScale = newAmplitudeScale;
            end
            power = obj.amplitudeScale * obj.maxAoutput; %in V
            theta = (obj.angle + obj.angleShift)*pi/180;
            
            
            obj.setPower(power*cos(theta), power*sin(theta))            
        end
        
        function setPower(obj, Ival, Qval)
            % Sets the I and Q output voltage
            newAmplitude = sqrt(Ival^2+Qval^2);
            if newAmplitude > obj.maxAoutput
                error('IQ output exeeds allowed value!')
            end
            obj.I.setValue(Ival)
            obj.Q.setValue(Qval)
        end       
    end
    
    methods (Static)
        function obj = create(jsonStruct)
            missingField = FactoryHelper.usualChecks(jsonStruct, IQSwitchNidaqControlled.NEEDED_FIELDS);
            if ~isnan(missingField)
                EventStation.anonymousError(['While trying to create an I2/Q2 part,', ...
                    'could not find "%s" field. Aborting'], ...
                    missingField);
            end
            
            I2Address = jsonStruct.I2;
            Q2Address = jsonStruct.Q2;
            obj = IQSwitchNidaqControlled(I2Address, Q2Address);
            
        end
    end
end