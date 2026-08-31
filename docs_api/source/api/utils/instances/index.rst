instances - Instance label operations
=====================================

The ``+utils/+instances`` package holds the algorithms that operate on **instance label
arrays** - volumes in which every object carries its own integer index. They are plain
array operations with no dependency on a network or a datastore, shared by DeepMIB
prediction, the Instance editor and the Model ribbon tab: cross-slice stitching of 2D
instances into 3D objects, splitting an index that covers several separate objects,
removing noise objects, and building a per-object index for interactive editing.

.. currentmodule:: utils.instances

.. automodule:: utils.instances
   :members:
