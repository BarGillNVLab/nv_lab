classdef ViewSpcmInImage < GuiComponent
    %VIEWSPCMINIMAGE wrapper for ViewSpcm for display in main image view
    
    properties (Constant)
        VIEW_HEIGHT = 100;
        VIEW_WIDTH = -1;
    end
    
    methods
        function obj = ViewSpcmInImage(parent,controller)
            panel = ViewExpandablePanel(parent, controller, 'SPCM Counter', @ViewSpcmInImage.popup);
            obj@GuiComponent(parent, controller);
            spcmView = ViewSpcm(panel, controller, ...
                'isStandalone', false, obj.VIEW_HEIGHT, obj.VIEW_WIDTH);
            obj.component = spcmView.component;
        end
    end     
       
    methods (Static)
        function popup
            GuiControllerSpcmCounter().start;
        end
        
    end
    
end

