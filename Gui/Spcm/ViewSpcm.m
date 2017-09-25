classdef ViewSpcm < ViewVBox
    %VIEWSPCM Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        vPlottingArea
        vControls
    end
    
    methods
        function obj = ViewSpcm(parent, controller)
            obj@ViewVBox(parent, controller,5);
            
            obj.vPlottingArea = ViewSpcmPlot(obj,controller);
            obj.vControls = ViewSpcmControls(obj,controller);
            
            obj.height = obj.vPlottingArea.height + obj.vControls.height + 10;
            obj.width = max([obj.vPlottingArea.width, obj.vControls.width]) + 10;
            
            obj.setHeights([obj.vPlottingArea.height, -1]);
        end
    end
    
end

