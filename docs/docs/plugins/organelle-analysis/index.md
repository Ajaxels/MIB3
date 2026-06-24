# Organelle Analysis Plugins

---

The **Organelle Analysis** plugins in **Microscopy Image Browser (MIB)** offer specialized tools for studying organelle structures and properties in microscopy images. These plugins are located in the `Plugins/Organelle Analysis` folder of your MIB installation and are automatically detected when MIB starts.

## Available Plugins

- **Golgi Orientation**  
  Calculates the relative orientation of Golgi apparatus with respect to the nucleus or cell
  boundary from segmented 3-D models, reporting a distance-distribution metric per cell.  
  [Details](golgi-orientation.md)

- **Granularity**  
  Analyzes model granularity, such as the ratio of sheets to tubules in endoplasmic reticulum (ER) morphology, aiding in structural studies.  
  [Details](granularity.md)

- **MCcalc**  
  Uses ray-tracing to detect and quantify contacts between organelles (e.g., mitochondria and ER), ideal for spatial relationship studies.  
  [Details](mccalc.md)

- **Surface Area 3D**  
  Computes the surface area of 3D-segmented objects, useful for volumetric analysis of organelles or structures.  
  [Details](surface-area-3d.md)

- **Thres Analysis for Objects**  
  Analyzes intensity properties of segmented objects with customizable thresholding, enhancing object-specific measurements.  
  [Details](thres-analysis-for-objects.md)

---

*Back to [MIB](../../index.md) | [User Interface](../../user-interface/index.md) | [Plugins](../index.md)*