models — Application Model
==========================

The ``+models`` package holds the central application state.
:class:`models.MibModel` owns the array of open :class:`core.MibDataset`
instances and fires events (``NewDataset``, ``ShowImage``,
``SliceChanged``, …) that all controllers observe.

.. currentmodule:: models

.. autoclass:: MibModel
   :members:
   :show-inheritance:
