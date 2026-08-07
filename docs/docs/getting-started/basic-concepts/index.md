# Basic Concepts

A few ideas underpin almost everything in MIB. Check this page once and the rest of the
documentation will read more easily. Each topic links to its full reference.

---

## Image layers

Every dataset in MIB is organised as a stack of co-registered **layers** sharing the same X, Y, Z
dimensions:

- **Image** - the core 2D-4D microscopy data (always present).
- **Selection** - a temporary scratch layer where segmentation tools work.
- **Model** - where finished segmentation results are stored (in some situations referred as **labels**).
- **Mask** - an auxiliary layer marking regions for independent analysis or filtering.

→ Full details: [Image Layers](../image-layers.md).

---

## Dataset types

MIB can hold an image in one of three memory/access modes, switchable in the
[Datasets panel](../../user-interface/panels/datasets/index.md#dataset-types):

- **Standard** - the whole dataset is in RAM; fastest, full editing.
- **Virtual** - read from disk on demand; browse files too large for RAM (view-only).
- **BigData** - pyramidal OME-Zarr v3 on disk and other pyramidal formats segment datasets far larger than RAM.

→ Full details: [Dataset types](../../user-interface/panels/datasets/index.md#dataset-types).

---

## Models and materials

A **model** is a set of labelled **materials**. To save memory, layers are packed together by
default, which limits the model to **63 materials**. Larger models (255, 65535, or 4294967295
materials) trade memory for capacity, and the 65535+ types change the Segmentation panel layout.

→ Full details: [Ribbon → Model → Convert type](../../user-interface/ribbon/model/index.md#convert-type).

---

## Buffers and sets

MIB holds each open dataset in a numbered **buffer**, and buffers are grouped into named **sets** of
ten. You can switch, duplicate, sync, or link buffer views from the Datasets panel.

**More than one set can be open at a time**, which is how unrelated groups of data are kept apart:
name one `Control` and another `Treatment`, and each keeps its own ten buffers. A set is also one
[Image Document](../../user-interface/image-document/index.md) tab, so switching sets switches the
whole working context rather than a single image.

→ Full details: [Datasets panel](../../user-interface/panels/datasets/index.md#sets).

---

*Back to [MIB](../../index.md) | [Getting started](../index.md)*
