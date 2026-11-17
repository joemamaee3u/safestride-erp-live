-- Align manufacturing components and bills of material with the IER outdoor catalog.
UPDATE public.products AS p
SET name = v.name
FROM (VALUES
  ('CMP-201', 'Tent fly fabric panel'),
  ('CMP-202', 'Aluminum tent pole section'),
  ('CMP-203', 'Tent stake and connector set'),
  ('CMP-204', 'LED headlamp module'),
  ('CMP-205', 'Rechargeable battery pack'),
  ('CMP-206', 'USB-C charging cable'),
  ('CMP-207', 'Adjustable headlamp strap'),
  ('CMP-208', 'Waterproof jacket shell'),
  ('CMP-209', 'Seam-sealing tape'),
  ('CMP-210', 'Water-resistant zipper'),
  ('CMP-211', 'Elastic jacket cuff pair'),
  ('CMP-212', 'Trekking pole cork grip pair'),
  ('CMP-213', 'Trekking pole wrist strap pair'),
  ('CMP-214', 'Outdoor gear storage pouch'),
  ('CMP-215', 'Recycled gear carton'),
  ('CMP-216', 'Aluminum trekking pole shaft'),
  ('CMP-217', 'Tungsten trekking pole tip pair'),
  ('CMP-218', 'Care and instruction label set'),
  ('CMP-219', 'Trekking pole locking collar pair')
) AS v(sku, name)
WHERE p.sku = v.sku AND p.category = 'Components';

-- Update the existing tent, headlamp, jacket, and bundle component quantities in place.
UPDATE public.erp_bom AS b
SET quantity_per = v.quantity_per
FROM (VALUES
  ('SSF-101', 'CMP-201', 1), ('SSF-101', 'CMP-202', 4), ('SSF-101', 'CMP-203', 8),
  ('SSF-101', 'CMP-215', 1), ('SSF-101', 'CMP-218', 1),
  ('SSF-102', 'CMP-204', 1), ('SSF-102', 'CMP-205', 1), ('SSF-102', 'CMP-206', 1),
  ('SSF-102', 'CMP-207', 1), ('SSF-102', 'CMP-215', 1),
  ('SSF-103', 'CMP-208', 1), ('SSF-103', 'CMP-209', 2), ('SSF-103', 'CMP-210', 1),
  ('SSF-103', 'CMP-218', 1),
  ('SSF-105', 'CMP-201', 1), ('SSF-105', 'CMP-202', 1), ('SSF-105', 'CMP-204', 1),
  ('SSF-105', 'CMP-205', 1), ('SSF-105', 'CMP-206', 1), ('SSF-105', 'CMP-207', 1),
  ('SSF-105', 'CMP-215', 1)
) AS v(parent_sku, component_sku, quantity_per)
JOIN public.products AS parent ON parent.sku = v.parent_sku
JOIN public.products AS component ON component.sku = v.component_sku
WHERE b.parent_product_id = parent.id AND b.component_product_id = component.id;

-- Replace the jacket's old pole component with a cuff pair.
UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 2
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-103' AND old_component.sku = 'CMP-202'
  AND replacement.sku = 'CMP-211'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

-- Shift the pole-set rows in an order that respects the parent/component unique key.
UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 2
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-104' AND old_component.sku = 'CMP-213'
  AND replacement.sku = 'CMP-216'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 2
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-104' AND old_component.sku = 'CMP-212'
  AND replacement.sku = 'CMP-213'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 2
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-104' AND old_component.sku = 'CMP-211'
  AND replacement.sku = 'CMP-212'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 2
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-104' AND old_component.sku = 'CMP-218'
  AND replacement.sku = 'CMP-219'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

-- The starter bundle now kits finished outdoor products instead of reflective-garment parts.
UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 1
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-105' AND old_component.sku = 'CMP-201'
  AND replacement.sku = 'SSF-101'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 1
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-105' AND old_component.sku = 'CMP-202'
  AND replacement.sku = 'IER-303'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 1
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-105' AND old_component.sku = 'CMP-204'
  AND replacement.sku = 'IER-304'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 1
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-105' AND old_component.sku = 'CMP-205'
  AND replacement.sku = 'IER-305'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 1
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-105' AND old_component.sku = 'CMP-206'
  AND replacement.sku = 'IER-306'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 1
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-105' AND old_component.sku = 'CMP-207'
  AND replacement.sku = 'IER-301'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

UPDATE public.erp_bom AS b
SET component_product_id = replacement.id, quantity_per = 1
FROM public.products AS parent, public.products AS old_component, public.products AS replacement
WHERE parent.sku = 'SSF-105' AND old_component.sku = 'CMP-215'
  AND replacement.sku = 'IER-307'
  AND b.parent_product_id = parent.id AND b.component_product_id = old_component.id;

-- Complete the trekking pole BOM and turn it into a seven-item outdoor starter kit.
INSERT INTO public.erp_bom (parent_product_id, component_product_id, quantity_per)
SELECT parent.id, component.id, 1
FROM public.products AS parent
CROSS JOIN public.products AS component
WHERE (parent.sku = 'SSF-104' AND component.sku = 'CMP-215')
   OR (parent.sku = 'SSF-105' AND component.sku IN ('IER-303', 'IER-304', 'IER-305', 'IER-306', 'IER-307'))
ON CONFLICT (parent_product_id, component_product_id)
DO UPDATE SET quantity_per = EXCLUDED.quantity_per;
