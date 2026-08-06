stitch — Image stitching core
=============================

The ``+utils/+stitch`` package holds the controller-independent, headless-testable
core of the :class:`controllers.Stitching` tool: layout builders, pairwise
registration (phase correlation and feature-based), the global least-squares
solver, canvas planning, and the three fusers (in-memory, streaming to OME-Zarr,
and straight out to standard image files).

.. currentmodule:: utils.stitch

.. automodule:: utils.stitch
   :members:
