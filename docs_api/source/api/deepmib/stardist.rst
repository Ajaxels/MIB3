stardist - StarDist 2D instance segmentation
=============================================

The ``+deepmib/+stardist`` package is a native MATLAB implementation of StarDist 2D
(Schmidt et al. 2018, Weigert et al. 2020): a U-Net predicts, at every pixel, an object
probability and the distances to the object boundary along a fixed set of rays, and a
non-maximum suppression keeps one star-convex polygon per object. The functions reproduce
StarDist 0.9.2 step by step (network, training targets, loss, normalisation, NMS, threshold
optimisation), so that the pretrained StarDist models run in MIB without Python and give the
same objects.

Typical prediction pipeline:

.. code-block:: matlab

   model = deepmib.stardist.loadPretrained('2D_versatile_fluo', deepMibDir);
   x = deepmib.stardist.normalizeImage(img, model.config.normalizePercentiles);
   [prob, dist] = deepmib.stardist.predictMaps(model.net, x, model.config);
   [points, scores, rayDist] = deepmib.stardist.nms(prob, dist, model.config.grid, model.config.probThresh, model.config.nmsThresh);
   labels = deepmib.stardist.polygonsToLabel(points, rayDist, scores, size(img, [1 2]));

.. currentmodule:: deepmib.stardist

.. automodule:: deepmib.stardist
   :members:
