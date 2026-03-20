function focusExample()

f = uifigure;
g = uigridlayout(f, [1, 2], "RowHeight", "fit");
b = uibutton(g, "ButtonPushedFcn", @onClick, "Text", "Open Dialog");
lb = uilabel(g);


    function onClick(~, ~)
        f2 = uifigure();
        g2 = uigridlayout(f2, [1, 2], "RowHeight", "fit", "BackgroundColor", "y");
        ef = uieditfield(g2);
        uibutton(g2, "Text", "OK", "ButtonPushedFcn", @onOK);
        focus(ef)

        function onOK( ~, ~ )

            lb.Text = ef.Value;
            delete(f2)

        end

    end

end