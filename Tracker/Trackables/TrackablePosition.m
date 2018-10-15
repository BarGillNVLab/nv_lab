classdef TrackablePosition < Trackable % & StageScanner
    %TRACKABLEPOSITION Makes sure that the experiment is still focused on the desired NV center 
    % The class uses a simple algorithm to counter mechanical drift
    % of the stage

    properties (SetAccess = private)
        stepNum = 0;	% int. Steps since beginning of tracking
        currAxis = 1;   % int. Numerical value of currently scanned axis (1 for X, etc.)

        mSignal
        mScanParams     % Object of class StageScanParams, to store current running scan
        stepSize        % nx1 double. Holds the current size of position step
        
        % Tracking options
        initialStepSize
        minimumStepSize
    end
    
     properties (SetAccess = private)
        %properties to use in the Newton-Raphson method. 
        
        sizeOfDifference %Holds the size of the movement we make in the stage in order to calculate numerical derivative
        currentValue %Holds the position of the stage in each step of the Newton Raphson Algorithm
        currentFirstDerivative %Holds the value of the first derivative in each step of the Newton Raphson Algorithm
        currentSecondDerivative %Holds the value of the second derivative in each step of the Newton Raphson Algorithm
        
    end
    
    
    properties % have setters
        mStageName
        mLaserName
        
        pixelTime
        nMaxIterations
    end
    
    properties (Constant, Hidden)
        EXP_NAME = 'trackablePosition';
    end
    
    properties (Constant)
        EVENT_STAGE_CHANGED = 'stageChanged'
        
        % Default properties
        NUM_MAX_ITERATIONS = 120;   % After that many steps, convergence is improbable
        PIXEL_TIME = 1 ;  % in seconds
        NUM_MAX_ITERATIONS_NEWTON_RAPHSON = 120; % written by lynn. After that many steps, convergence is improbable
        
        % vector constants, for [X Y Z]
        INITIAL_STEP_VECTOR = [0.05 0.05 0.1];    %[0.1 0.1 0.05];
        MINIMUM_STEP_VECTOR = [0.02 0.02 0.02]; %[0.01 0.01 0.01];
        STEP_RATIO_VECTOR = 0.5*ones(1, 3);
        ZERO_VECTOR = [0 0 0];
        
        HISTORY_FIELDS = {'position', 'step', 'time', 'value'}
        
        DEFAULT_CONTINUOUS_TRACKING = false;
        
        SIZE_OF_DIFFERENCE = 1e-3; % dx to use in the newthon-raphson method. temp. written by lynn.
        ALMOST_ZERO = 1e-10;
    end
    
    methods
        function obj = TrackablePosition(stageName)
            obj@Trackable;
            
            % Get stage
            if exist('stageName', 'var')
                obj.mStageName = stageName;
                stage = getObjByName(stageName);
                assert(stage.isScannable)
            else
                stage = JsonInfoReader.getDefaultObject('stages');
                obj.mStageName = stage.NAME;
                
                % Obselete code, might be useful in the future:
%                 stages = ClassStage.getScannableStages;
%                 stage = stages{1};
%                 obj.mStageName = stage.NAME;
            end
            
            % We also need these:
            phAxes = stage.getAxis(stage.availableAxes);
            obj.mScanParams = StageScanParams;
            obj.mLaserName = LaserGate.GREEN_LASER_NAME;
            
            % Set default tracking properties
            obj.initialStepSize = obj.INITIAL_STEP_VECTOR(phAxes);
            obj.minimumStepSize = obj.MINIMUM_STEP_VECTOR(phAxes);
            obj.pixelTime = obj.PIXEL_TIME;
            obj.nMaxIterations = obj.NUM_MAX_ITERATIONS;
            
            %written by lynn
            obj.sizeOfDifference = obj.SIZE_OF_DIFFERENCE;
            obj.currentValue = NaN*ones(1,length(ClassStage.SCAN_AXES));
            obj.currentFirstDerivative = ones(1,length(ClassStage.SCAN_AXES));
            obj.currentSecondDerivative = NaN*ones(1,length(ClassStage.SCAN_AXES));
        end
    end
    
    %% Overridden from Experiment
    methods
        function prepare(obj)
            
            %%%% Initialize %%%%
            obj.resetAlgorithm;
            obj.isCurrentlyTracking = true;
            stage = getObjByName(obj.mStageName);
            
            spcm = getObjByName(Spcm.NAME);
            spcm.setSPCMEnable(true);
            
            laser = getObjByName(obj.mLaserName);
            laser.isOn = true;
            
            %%%% Get initial position and signal value, for history %%%%
            % Set parameters for scan
            phAxes = stage.getAxis(stage.availableAxes);
            sp = obj.mScanParams;
            sp.fixedPos = stage.Pos(phAxes);
            sp.isFixed = true(size(sp.isFixed));    % all axes are fixed on initalization
            sp.pixelTime = obj.pixelTime;
            scanner = StageScanner.init;
            if ~ischar(scanner.mStageName) || ~strcmp(scanner.mStageName, obj.mStageName)
                scanner.switchTo(obj.mStageName)
            end
            
            % We are up and running. Now show GUI, so we can actually see
            % what's going on
            gui = GuiControllerTrackablePosition;
            try
                gui.start();
            catch err
                EventStation.anonymousWarning('Tracker window could not open. Continuing tracking nonetheless.');
                err2warning(err);
            end
            
            obj.mSignal = scanner.scanPoint(stage, spcm, sp);
            obj.recordCurrentState;     % record starting point (time == 0)
        end
        
        function perform(obj)
            % Execution of at least one iteration is acheived by using
            % {while(true) {statements} if(condition) {break}}
            while true
                obj.NewtonRaphsonAlgorithm;
                obj.recordCurrentState;
                if ~obj.isRunningContinuously; break; end
                obj.sendEventTrackableExpEnded;
            end

        end
        
        function analyze(obj) %#ok<MANU>
            % No analysis required (yet?)
        end
    end
       
    %% Overridden from Trackable
    methods
        function resetTrack(obj)
            obj.resetAlgorithm;
            obj.timer = [];
            obj.clearHistory;
        end
        
        function params = getAllTrackalbeParameter(obj) %#ok<MANU>
        % Returns a cell of values/paramters from the trackable experiment
        params = NaN;
        end
        
        function str = textOutput(obj)
            stage = getObjByName(obj.mStageName);
            phAxes = stage.getAxis(stage.availableAxes);
            
            if all(obj.stepSize <= obj.MINIMUM_STEP_VECTOR(phAxes))
                str = sprintf('Local maximum was found in %u steps', obj.stepNum);
            elseif obj.stopFlag
                str = 'Operation terminated by user';
            elseif obj.isDivergent
                str = 'Maximum number of iterations reached without convergence';
            else
                str = 'This shouldn''t have happenned...';
            end
        end
    end
    
    %% setters
    methods
        function set.mStageName(obj, newStageName)
            if ~strcmp(obj.mStageName, newStageName)    % MATLAB doc says this check is done internally, but we don't count on it
                if obj.isCurrentlyTracking
                    obj.sendWarning('Can''t switch stage while tracking. Try again later.')
                else
                    obj.mStageName = newStageName;
                    obj.sendEvent(struct(obj.EVENT_STAGE_CHANGED, true));
                end
                
                
            end
        end
        
        function setMinimumStepSize(obj, index, newSize)
            % Allows for vector input
            try
                if length(newSize) ~= length(index)
                    error('Inputs are incompatible. Cannot Complete action.')
                elseif  any (index > length(obj.minimumStepSize)) || any(newSize <= 0)
                    error('Cannot set this step size!')
                elseif any(newSize > obj.initialStepSize(index))
                    error('Minimum step size can''t be larger than the initial step size, or tracking will LITERALLY take forever.')
                elseif any(newSize <= 0)
                    error('There is no point in setting negative step size.')
                end
                obj.minimumStepSize(index) = newSize;
            catch err
                obj.sendError(err.message);
            end
        end
        
        function setInitialStepSize(obj, index, newSize)
            % Allows for vector input
            try
                if length(newSize) ~= length(index)
                    error('Inputs are incompatible. Cannot Complete action.')
                elseif  any (index > length(obj.minimumStepSize)) || any(newSize <= 0)
                    error('Cannot set this step size!')
                elseif any(newSize < obj.minimumStepSize(index))
                    error('Initial step size can''t be smaller than the minimum step size, or tracking will LITERALLY take forever.')
                end
                obj.initialStepSize(index) = newSize;
            catch err
                obj.sendError(err.message);
            end
        end
        
        function set.pixelTime(obj, newTime)
            if ~(newTime > 0)       % False if zero or less, and also if not a number
                obj.sendError('Pixel time must be a positive number');
            end
            obj.pixelTime = newTime;
        end
        
        function set.nMaxIterations(obj, newNum)
            if isnumeric(newNum)
                num = uint32(newNum);
            else
                num = uint32(str2double(newNum));
            end
            
            if num == 0
                errorMsg = sprintf('We don''t allow for %s iterations', newNum);
                obj.sendError(errorMsg);
            elseif num ~= newNum
                obj.sendWarning('Maximum number of iterations was rounded to nearest integer')
            end
                obj.nMaxIterations = num;     
        end
        
    end
        
    methods (Access = private)
        function recordCurrentState(obj)
            record = struct;
            record.position = obj.mScanParams.fixedPos;
            record.step = obj.stepSize;
            record.value = obj.mSignal;
            record.time = obj.myToc;  % personalized toc function
            
            obj.mHistory{end+1} = record;
            obj.sendEventTrackableUpdated;
        end
    end

    %% Scanning algorithms.
    % For now, only one, should include more in the future
    methods
        function HovavAlgorithm(obj)
            % Moves axis-wise (cyclicly) to the direction of the
            % derivative. In other words, this is a simple axis-wise form
            % of gradient ascent.
            stage = getObjByName(obj.mStageName);
            spcm = getObjByName(Spcm.NAME);
            phAxes = stage.getAxis(stage.availableAxes);
            len = length(phAxes);
            scanner = StageScanner.init;
            
            % Initialize scan parameters for search
            sp = obj.mScanParams;
            sp.fixedPos = stage.Pos(phAxes);
            sp.pixelTime = obj.pixelTime;
            
            tracker = getObjByName(Tracker.NAME);
            thresh = tracker.kcpsThreshholdFraction;
            
            while ~obj.stopFlag && any(obj.stepSize > obj.MINIMUM_STEP_VECTOR(phAxes)) && ~obj.isDivergent
                if obj.stepSize(obj.currAxis) > obj.MINIMUM_STEP_VECTOR(obj.currAxis)
                    obj.stepNum = obj.stepNum + 1;
                    pos = sp.fixedPos(obj.currAxis);
                    step = obj.stepSize(obj.currAxis);
                    
                    % scan to find forward and backward 'derivative'
                    % backward
                    sp.fixedPos(obj.currAxis) = pos - step;
                    signals(1) = scanner.scanPoint(stage, spcm, sp);
                    % current
                    sp.fixedPos(obj.currAxis) = pos;
                    signals(2) = scanner.scanPoint(stage, spcm, sp);
                    % forward
                    sp.fixedPos(obj.currAxis) = pos + step;
                    signals(3) = scanner.scanPoint(stage, spcm, sp);
                    
                    shouldMoveBack = Tracker.isDifferenceAboveThreshhold(signals(1), signals(2), thresh);
                    shouldMoveFwd = Tracker.isDifferenceAboveThreshhold(signals(3), signals(2), thresh);
                    
                    shouldContinue = false;
                    if shouldMoveBack
                        if shouldMoveFwd
                            % local minimum; don't move
                            disp('Conflict.... make longer scans?')
                        else
                            % should go back and look for maximum:
                            % prepare for next step
                            newStep = -step;
                            pos = pos + newStep;
                            newSignal = signals(1);   % value @ best position yet
                            shouldContinue = true;
                        end
                        
                    else
                        if shouldMoveFwd
                            % should go forward and look for maximum:
                            % prepare for next step
                            newStep = step;
                            pos = pos + newStep;
                            newSignal = signals(3);   % value @ best position yet
                            shouldContinue = true;
                        else
                            % local maximum or plateau; don't move
                        end
                    end
                    
                    while shouldContinue
                        if obj.isDivergent || obj.stopFlag; return; end
                        % we are still iterating; save current position before moving on
                        obj.mSignal = newSignal;    % Save value @ best position yet
                        obj.recordCurrentState;
                        
                        obj.stepNum = obj.stepNum + 1;
                        % New pos = (pos + step), if you should move forward;
                        %           (pos - step), if you should move backwards
                        pos = pos + newStep;
                        sp.fixedPos(obj.currAxis) = pos;
                        sp.isFixed(obj.currAxis) = true;
                        newSignal = scanner.scanPoint(stage, spcm, sp);
                        
                        shouldContinue = Tracker.isDifferenceAboveThreshhold(newSignal, obj.mSignal, thresh);
                    end
                    obj.stepSize(obj.currAxis) = step/2;
                end
                sp.isFixed(obj.currAxis) = true;        % We are done with this axis, for now
                obj.currAxis = mod(obj.currAxis, len) + 1; % Cycle through 1:len
            end
        end
        
        function resetAlgorithm(obj)
            obj.stopFlag = false;
            obj.stepNum = 0;
            obj.currAxis = 1;
            
            obj.mSignal = [];
            obj.mScanParams = StageScanParams;
            obj.stepSize = obj.initialStepSize;
            
            obj.currentValue = NaN*ones(1,length(ClassStage.SCAN_AXES));
            obj.currentFirstDerivative = ones(1,length(ClassStage.SCAN_AXES));
            obj.currentSecondDerivative = NaN*ones(1,length(ClassStage.SCAN_AXES));
            
        end
        
        function tf = isDivergent(obj)
            % If we arrive at the maximum number of iterations, we assume
            % the tracking sequence will not converge, and we stop it
            tf = (obj.stepNum >= obj.NUM_MAX_ITERATIONS);
        end
        
        % a beta function that runs the search algorithem of newton raphson
        function NewtonRaphsonAlgorithm(obj)
            
            stage = getObjByName(obj.mStageName);
            spcm = getObjByName(Spcm.NAME);
            phAxes = stage.getAxis(stage.availableAxes);
            len = length(phAxes);
            scanner = StageScanner.init;
            
            % Initialize scan parameters for search
            sp = obj.mScanParams;
            sp.fixedPos = stage.Pos(phAxes);
            sp.pixelTime = obj.pixelTime;
            obj.currentValue = sp.fixedPos;   
            
            while obj.currAxis <= len
                while ~obj.stopFlag && ~obj.failToConverge && obj.currentFirstDerivative(obj.currAxis) > obj.ALMOST_ZERO

                    obj.stepNum = obj.stepNum + 1;
                    pos = obj.currentValue(obj.currAxis);

                    sp.fixedPos(obj.currAxis) = pos + obj.SIZE_OF_DIFFERENCE;
    %                     firstScanResult = scanner.scanPoint(stage, spcm, sp);
                    firstScanResult = scanner.dummyScanGaussianPoint(sp.fixedPos);

                    sp.fixedPos(obj.currAxis) = pos;
    %                     currentScanResult = scanner.scanPoint(stage, spcm, sp);
                    currentScanResult = scanner.dummyScanGaussianPoint(sp.fixedPos);

                    sp.fixedPos(obj.currAxis) = pos - obj.SIZE_OF_DIFFERENCE;
    %                     secondScanResult = scanner.scanPoint(stage, spcm, sp);
                    secondScanResult = scanner.dummyScanGaussianPoint(sp.fixedPos);

                    obj.currentFirstDerivative(obj.currAxis) = obj.calculateFirstDerivative(firstScanResult,secondScanResult);

                    obj.currentSecondDerivative(obj.currAxis) = obj.calculateSecondDerivative(firstScanResult,secondScanResult,currentScanResult);

                    if obj.currentSecondDerivative(obj.currAxis) ~= 0
                        obj.currentValue(obj.currAxis) = obj.currentValue(obj.currAxis) - (obj.currentFirstDerivative(obj.currAxis)/obj.currentSecondDerivative(obj.currAxis));
                    end
                end
                sp.isFixed(obj.currAxis) = true;        % We are done with this axis, for now
                obj.currAxis = obj.currAxis + 1;
                obj.stepNum = 0;
            end
        end
        
        % a function that holds a boolean value represents whether the
        % newthon-raphson algorithm failed to converge.
        % for now based on number of steps. may have changes.
        function ftc = failToConverge(obj)
            ftc = (obj.stepNum >= obj.NUM_MAX_ITERATIONS_NEWTON_RAPHSON) || (obj.currentSecondDerivative(obj.currAxis) == 0);
        end
    end
    
    methods (Static)
        % a function that calculates the first derivative for each step in
        % the newton raphson algorithm.
        % param1 - firstScanResult - The result of the scan at the current point plus dx
        % param2 - secondScanResult - The result of the scan at the current point minus dx
        function firstDerivative = calculateFirstDerivative(firstScanResult, secondScanResult)
            firstDerivative = (firstScanResult - secondScanResult) / (2*TrackablePosition.SIZE_OF_DIFFERENCE);
        end
        
        % a function that calculates the second derivative for each step in
        % the newton raphson algorithm.
        % param1 - firstScanResult - The result of the scan at the current point plus dx
        % param2 - secondScanResult - The result of the scan at the current point minus dx
        % param3 - currentScanResult - The result of the scan at the current point
        function secondDerivative = calculateSecondDerivative(firstScanResult, secondScanResult, currentScanResult)
            secondDerivative = (firstScanResult + secondScanResult - 2*currentScanResult)/ (TrackablePosition.SIZE_OF_DIFFERENCE^2);
        end
    end
end

