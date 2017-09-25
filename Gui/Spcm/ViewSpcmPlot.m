classdef ViewSpcmPlot < GuiComponent & EventListener
    %VIEWSPCMPLOT Shows recent readings of SPCM
    %   Detailed explanation goes here
    
    properties
        wrap            % positive integer, how many records in plot

        vAxes           % axes view, to use for the plotting
        cbxUsingWrap
        edtWrap
    end
    properties(Constant = true)
        BOTTOM_LABEL = 'Result Number'; % Text for horiz. axis
        LEFT_LABEL = 'kCounts/sec';     % Text for vert. axis
        
        DEFAULT_WRAP_VALUE = 50;        % Value of wrap set in initiation
        DEFAULT_USING_WRAP = true;  % boolean, does this window uses wrap
    end
    
    methods
        function obj = ViewSpcmPlot(parent, controller)
            obj@GuiComponent(parent, controller);
            obj@EventListener(SpcmCounter.NAME);
                        
            obj.component = uicontainer('parent', parent.component);
            obj.vAxes = axes('Parent', obj.component, 'ActivePositionProperty', 'outerposition');
            
            %%%% Pane for wrapping data %%%%
            obj.vboxWrap = uix.HBox('Parent',obj.component);
            obj.cbxUsingWrap = uicontrol(obj.PROP_CHECKBOX{:}, 'Parent', obj.vboxWrap, 'Value', obj.DEFAULT_USING_WRAP, 'String', 'Use wrap?');
            uicontrol(obj.PROP_LABEL{:}, 'Parent', obj.vboxWrap, 'String', '# of Pts');
            obj.edtWrap = uicontrol(obj.PROP_EDIT{:}, 'Parent', obj.vboxWrap, 'String', obj.DEFAULT_WRAP_VALUE);
            
            %%%% Define size %%%%
            obj.width = 450;            
            obj.height = 300;
            
        end
        
        %%%% Callbacks %%%%
        % function cbxUsingWrapCallback isn't needed
        function edtWrapCallback(obj,~,~)
            if ~ValidationHelper.isValuePositiveInteger()
                
                
            end
        end
    end
    
    %% overridden from EventListener
    methods
        % when event happens, this function jumps.
        % event is the event sent from the EventSender
        function onEvent(obj, event)
            if isfield(event.extraInfo, SpcmCounter.EVENT_SPCM_COUNTER_UPDATED)
                spcmCount = getObjByName(SpcmCounter.NAME);
                if obj.parent.vControls.isUsingWrap
                    wrap = obj.parent.vControls.wrap;
                    xVector = 1:wrap;
                    difference = wrap - length(spcmCount.records);
                    if difference>=0
                        data = [spcmCount.records NaN(1,difference)];
                    else
                        data = spcmCount.records(end-wrap:end);
                    end
                else
                    data = spcmCount.records;
                    xVector = 1:length(data);
                end
                dimNum = 1;
                AxesHelper.fillAxes(obj.vAxes, data, dimNum, xVector, nan, obj.BOTTOM_LABEL, obj.LEFT_LABEL);
                
            end
        end
    end
    
end

