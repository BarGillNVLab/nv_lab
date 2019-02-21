classdef ViewSpcm < ViewVBox & EventListener
    %VIEWSPCM view for the SPCM counter
    % This view receives data from the SPCM counter, and displays it
    % according to the requirement of the user (especially, determinines
    % value for wrap (maximum number of data points presented). It can also
    % turn the the SPCMC on and off.
    
    properties
        vAxes           % axes view, to use for the plotting
        btnPopout
        
        btnStartStop
        btnReset
        edtIntegrationTime
        
        wrap            % positive integer, how many records in plot
        cbxUsingWrap
        edtWrap
        
        isStandalone = false;
    end
    
    properties (Constant)
        BOTTOM_LABEL = 'time [sec]'; % Text for horiz. axis
        LEFT_LABEL = 'kcps';     % Text for vert. axis
        
        DEFAULT_WRAP_VALUE = 50;    % Value of wrap set in initiation
        DEFAULT_USING_WRAP = true;  % boolean, does this window uses wrap
    end
    
    methods
        function obj = ViewSpcm(parent, controller, varargin)
            padding = 5;
            obj@ViewVBox(parent, controller, padding);
            obj@EventListener(SpcmCounter.NAME);
            
            obj.wrap = obj.DEFAULT_WRAP_VALUE;

            if strcmp(varargin{1}, 'isStandalone')
                % This is the value for obj.isStandalone
                obj.isStandalone = varargin{2};
            end
            
            %%% Plot Area %%%
            % Set initial values for properties of axes 
            obj.vAxes = axes('Parent', obj.component, ...
                'ActivePositionProperty', 'outerposition');
            AxesHelper.fill(obj.vAxes, AxesHelper.DEFAULT_Y, 1, AxesHelper.DEFAULT_X, [], obj.BOTTOM_LABEL, obj.LEFT_LABEL);
            if obj.isStandalone
                obj.vAxes.FontSize = 20;
            end
            axes()
            
            %%% Buttons / Controls %%%
            hboxButtons = uix.HBox('Parent', obj.component, ...
                'Spacing', 3);
            
            % SPCM Controls Panel
            panelControls = uix.Panel('Parent', hboxButtons, ...
                'Title', 'SPCM Controls');
            hboxControls = uix.HBox('Parent', panelControls, ...
                'Spacing', 3);
            
            obj.btnStartStop = ButtonStartStop(hboxControls);
                obj.btnStartStop.startCallback = @obj.btnStartCallback;
                obj.btnStartStop.stopCallback = @obj.btnStopCallback;
            obj.btnReset = uicontrol(obj.PROP_BUTTON{:}, ...
                'Parent', hboxControls, ...
                'String', 'Reset', ...
                'Callback', @obj.btnResetCallback);
            
            % Integration time column %
            defaultTime = SpcmCounter.INTEGRATION_TIME_DEFAULT_MILLISEC;
            vboxIntegrationTime =  uix.VBox('Parent', hboxControls, ...
                'Spacing', 1, 'Padding', 1);
            uicontrol(obj.PROP_LABEL{:}, ...
                'Parent', vboxIntegrationTime, ...
                'String', 'Integration (ms)');
            obj.edtIntegrationTime = uicontrol(obj.PROP_EDIT{:}, ...
                'Parent', vboxIntegrationTime, ...
                'String', num2str(defaultTime), ...
                'Callback', @obj.edtIntegrationTimeCallback);
            vboxIntegrationTime.Heights = [-1 -1];
            
            hboxControls.Widths = [-1, -1, -1.5];
            
            % Wrap Panel %
            panelWrap = uix.Panel('Parent', hboxButtons, ...
                'Title', 'Wrap');
            hboxWrapMain = uix.HBox('Parent', panelWrap, ...
                'Spacing', 1, 'Padding', 1);
            obj.cbxUsingWrap = uicontrol(obj.PROP_CHECKBOX{:}, ...
                'Parent', hboxWrapMain, ...
                'Value', obj.DEFAULT_USING_WRAP, ...
                'Callback', @obj.cbxUsingWrapCallback);
            vboxWrapNumber = uix.VBox('Parent', hboxWrapMain);
                uicontrol(obj.PROP_LABEL{:}, 'Parent', vboxWrapNumber, ...
                    'String', '# of Pts');
                obj.edtWrap = uicontrol(obj.PROP_EDIT{:}, ...
                    'Parent', vboxWrapNumber, ...
                    'String', obj.DEFAULT_WRAP_VALUE, ...
                    'Callback', @obj.edtWrapCallback);
                vboxWrapNumber.Heights = [-1, -1];
            hboxWrapMain.Widths = [15, -1];
            
            hboxButtons.Widths = [-3, -1];

            obj.update;     % There might already be records in the counter
            
            %%% Define size %%%
            % Default values
            obj.height = 500;
            obj.width = 850;
            
            switch length(varargin)
                case 2
                    if ~strcmp(varargin{1}, 'isStandalone')
                        % not a standalone
                        obj.height = varargin{1};
                        obj.width = varargin{2};
                    end
                case 4
                    if strcmp(varargin{1}, 'isStandalone')
                        heightArgIndex = 3;
                    else
                        heightArgIndex = 1;
                    end
                    obj.height = varargin{heightArgIndex};
                    obj.width = varargin{heightArgIndex+1};
            end
            
            controlsHeight = 80;
            obj.setHeights([-1, controlsHeight]);
        end

        
        
        function tf = isUsingWrap(obj)
            tf = obj.cbxUsingWrap.Value;
        end
        
        function refresh(obj)
            % Just uicontrols, not axes
            try
                spcmCount = getObjByName(SpcmCounter.NAME);
                obj.edtIntegrationTime.String = spcmCount.integrationTimeMillisec;
                
                obj.btnStartStop.isRunning = spcmCount.isRunning;
                
            catch
                % The counter is unavailable
                obj.btnStartStop.isRunning = false;
            end
        end
        
        function update(obj)
            % Axes AND uicontrols
            
            try
                counter = getObjByName(SpcmCounter.NAME);
            catch
                return
            end
            
            %%% Plot
            % Get plot data
            if obj.isUsingWrap
                [time, kcps, std] = counter.getRecords(obj.wrap);
            else
                [time, kcps, std] = counter.getRecords;
            end
            dimNum = 1;
            AxesHelper.update(obj.vAxes, kcps, dimNum, time, nan, std);
            obj.vAxes.Children.HitTest = 'off'; % So as not to be interacted by "marker" cursor
            
            set(obj.vAxes, 'XLim', [-inf, inf]);	% Creates smooth "sweep" of data
            drawnow;                                % consider using animatedline
            
            % Update uicontrols
            obj.refresh;
        end
        
        %%%% Callbacks %%%%
        function cbxUsingWrapCallback(obj, ~, ~)
            obj.recolor(obj.edtWrap, ~obj.isUsingWrap)
            obj.update;
        end
        function edtWrapCallback(obj, ~, ~)
            if ~ValidationHelper.isValuePositiveInteger(obj.edtWrap.String)
                EventStation.anonymousWarning('Wrap needs to be a positive integer! Reverting.')
                obj.edtWrap.String = obj.wrap;
            end
            obj.wrap = str2double(obj.edtWrap.String);
            obj.update;
        end
        function btnStartCallback(obj, ~, ~)
            spcmCount = obj.getCounter;
            spcmCount.run;
        end
        function btnStopCallback(obj, ~, ~)
            spcmCount = obj.getCounter;
            spcmCount.pause;
        end
        function btnResetCallback(obj, ~ ,~)
            spcmCount = obj.getCounter;
            spcmCount.resetHistory;
        end
        function edtIntegrationTimeCallback(obj, ~, ~) 
            spcmCount = obj.getCounter;
            spcmCount.integrationTimeMillisec = str2double(obj.edtIntegrationTime.String);
            % The counter will take care of the rest
        end
        
    end
    
    methods (Static)
        function spcmCounter = getCounter
            try
                spcmCounter = getObjByName(SpcmCounter.NAME);
            catch
                spcmCounter = SpcmCounter;
            end
        end
    end
    
    %% overridden from EventListener
    methods
        % When events happens, this function jumps.
        % event is the event sent from the EventSender
        function onEvent(obj, event)
            spcmCounter = event.creator;
            if isfield(event.extraInfo, spcmCounter.EVENT_DATA_UPDATED)   % event = update
                obj.update;
            else
                obj.refresh;
            end
            if isfield(event.extraInfo, SpcmCounter.EVENT_SPCM_COUNTER_RESET)    % event = reset
                line = obj.vAxes.Children;
                delete(line);
            end
        end
    end
    
end
