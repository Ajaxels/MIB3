# Tutorials Plugins

---

The **Tutorials** plugins in **Microscopy Image Browser (MIB)** provide examples to help users learn plugin development for MIB. 
These plugins are located in the `Plugins/Tutorials` folder of your MIB installation and are automatically detected when MIB starts.

## Available Plugins

- **GUI Tutorial**  
  The reference App Designer GUI plugin — four operations (Crop, Resize, Convert, Invert) showing
  the controller/view structure, the constructor pattern, and MIB3 data access. Start here.  
  [Details](gui-tutorial.md)

- **GUI Tutorial (Batch)**  
  Extends GUI Tutorial with full batch-processing support: the `BatchOpt` parameter system, macro
  record/replay, and headless execution.  
  [Details](gui-tutorial-batch.md)

- **Demo Plugin**  
  The minimal batch-compatible App Designer plugin — demonstrates how each widget type round-trips
  through `BatchOpt` and the three calling modes (interactive, headless, query).  
  [Details](mib-app-design-plugin.md)

- **MIB Plugin Without GUI**  
  Demonstrates a simple plugin without a graphical interface, focusing on backend functionality for quick scripting.  
  [Details](mib-plugin-without-gui.md)

---

*Back to [MIB](../../index.md) | [User Interface](../../user-interface/index.md) | [Plugins](../index.md)*