-- Retire legacy running-only demo SKUs from public browsing while preserving their history.
UPDATE public.products
SET is_active = false
WHERE sku ~ '^(RUN|KIT)[0-9]{3}$';

UPDATE public.products
SET name = 'Summit Trail Cap',
    category = 'Accessories',
    price = 32.00,
    cost = 11.00,
    is_active = true
WHERE sku = 'CMP-220';
