core — Core Data Classes
========================

.. currentmodule:: core

The ``+core`` package contains all data-holding classes.  A
:class:`core.MibDataset` instance represents one open dataset and owns
the image, label, mask, selection, annotation, and line-tracing layers.

Dataset and image layers
------------------------

.. toctree::
   :maxdepth: 1

   MibDataset
   MibImage
   MibVirtualImage
   MibBigDataImage

Label layers
------------

Two branches, and which one a store lands on decides what it can hold.
:class:`core.MibLabels63` packs material, mask and selection into one byte, so its
descendants top out at 63 materials but are editable; :class:`core.MibLabels` keeps
the layers separate and reaches 65535 or more::

    MibImage
    +-- MibLabels63 -- MibBigDataLabels -- MibBigDataLabelsZarr2   (packed byte, editable store)
    +-- MibLabels    -- MibBigDataLabelsIndex                      (separate layers, read-only)

.. toctree::
   :maxdepth: 1

   MibLabels
   MibLabels63
   MibBigDataLabels
   MibBigDataLabelsZarr2
   MibBigDataLabelsIndex

Overlays and annotations
------------------------

.. toctree::
   :maxdepth: 1

   Annotations
   Lines3D
   Measurements
   RoiRegion

Supporting classes
------------------

.. toctree::
   :maxdepth: 1

   MibBackup
   ChildView
   MibIconCache
   PoolWaitbar
   ToggleEventData
