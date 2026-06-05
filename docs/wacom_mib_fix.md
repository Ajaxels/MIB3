## Wacom Pen Draws Only a Spot Instead of a Continuous Stroke

If using a Wacom pen on a touch screen, the brush tool may register only a single dot instead of
a continuous stroke when the pen tip is set to **Click** (left mouse button). This happens because
Windows Ink — enabled by default in the Wacom driver — communicates pen input through the Windows
Ink API, which treats a pen touch as a stylus tap rather than a held-down mouse drag. As a result,
MIB receives only a single `WindowButtonDown` event with no subsequent motion, producing a spot.

**Fix: disable Windows Ink for MIB in the Wacom driver**

1. Launch MIB so it appears in the Windows process list.
2. Open **Wacom Tablet Properties** (via Wacom Desktop Center → Pen Settings).
3. In the **Application** panel on the left, click **"+"** and select **MATLAB** from the list of
   running applications.
4. With MATLAB selected, switch to the **Mapping** tab.
5. Uncheck **"Use Windows Ink"** and click **OK**.
6. Restart MATLAB.

With Windows Ink disabled for MATLAB, the driver falls back to the WinTab API, which correctly
delivers continuous motion events while the pen tip is held down — making the brush tool behave
identically to a standard mouse.
