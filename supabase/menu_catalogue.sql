-- Expanded illustrated vendor catalogue (safe to re-run).
alter table public.menu_items add column if not exists category text not null default 'Menu item';
alter table public.menu_items add column if not exists image_url text not null default '';

create temporary table jdt_menu_catalogue (
 vendor_name text,name text,description text,price numeric,category text,image_url text
) on commit drop;

insert into jdt_menu_catalogue values
('JDT Hospitality Kitchen','JDT Signature Beef Burger','Grilled beef patty, cheddar, lettuce and house sauce',28.00,'Burgers & mains','https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=900&q=85'),
('JDT Hospitality Kitchen','Smoky BBQ Chicken Burger','Grilled chicken, smoky BBQ glaze and crisp lettuce',26.00,'Burgers & mains','https://images.unsplash.com/photo-1606755962773-d324e0a13086?w=900&q=85'),
('JDT Hospitality Kitchen','Grilled Chicken Wrap','Seasoned chicken, fresh greens and creamy dressing',22.00,'Light bites','https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=900&q=85'),
('JDT Hospitality Kitchen','Crispy Chicken & Fries','Golden fried chicken served with fries',25.00,'Burgers & mains','https://images.unsplash.com/photo-1562967914-608f82629710?w=900&q=85'),
('JDT Hospitality Kitchen','Loaded Beef Nachos','Crispy nachos topped with beef, cheese and salsa',24.00,'Light bites','https://images.unsplash.com/photo-1513456852971-30c0b8199d4d?w=900&q=85'),
('Premium Lounge','Premium Fruit Platter','Seasonal sliced fruit, prepared for sharing',25.00,'Fresh & healthy','https://images.unsplash.com/photo-1490474418585-ba9bad8fd0ea?w=900&q=85'),
('Premium Lounge','Caesar Chicken Salad','Romaine lettuce, grilled chicken, parmesan and croutons',27.00,'Fresh & healthy','https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=900&q=85'),
('Premium Lounge','Smoked Salmon Sandwich','Smoked salmon, cream cheese and fresh greens',32.00,'Premium bites','https://images.unsplash.com/photo-1528735602780-2552fd46c7af?w=900&q=85'),
('Premium Lounge','Chocolate Brownie','Rich chocolate brownie served as a sweet treat',14.00,'Desserts','https://images.unsplash.com/photo-1606313564200-e75d5e30476c?w=900&q=85'),
('Premium Lounge','Cheese & Crackers Board','A selection of cheeses, crackers and fruit',38.00,'Premium bites','https://images.unsplash.com/photo-1490474418585-ba9bad8fd0ea?w=900&q=85'),
('Stadium Beverage Service','Fresh Orange Juice','Chilled freshly prepared orange juice',12.00,'Fresh drinks','https://images.unsplash.com/photo-1613478223719-2ab802602423?w=900&q=85'),
('Stadium Beverage Service','Iced Lemon Tea','Refreshing iced tea with lemon',9.00,'Cold drinks','https://images.unsplash.com/photo-1556679343-c7306c1976bc?w=900&q=85'),
('Stadium Beverage Service','Sparkling Water','Chilled sparkling mineral water',8.00,'Water','https://images.unsplash.com/photo-1600271886742-f049cd451bba?w=900&q=85'),
('Stadium Beverage Service','Iced Latte','Espresso with chilled milk over ice',14.00,'Coffee','https://images.unsplash.com/photo-1461023058943-07fcbe16d735?w=900&q=85'),
('Stadium Beverage Service','Fresh Coconut Water','Chilled coconut water',13.00,'Fresh drinks','https://images.unsplash.com/photo-1550583724-b2692b85b150?w=900&q=85'),
('Concessions','Classic Hot Dog','Grilled sausage in a soft bun with condiments',16.00,'Stadium favourites','https://images.unsplash.com/photo-1612392062126-3b1b1e7e7b8c?w=900&q=85'),
('Concessions','Nachos & Cheese','Crunchy nachos with warm cheese dip',18.00,'Stadium favourites','https://images.unsplash.com/photo-1513456852971-30c0b8199d4d?w=900&q=85'),
('Concessions','Seasoned French Fries','Golden fries with house seasoning',12.00,'Sides','https://images.unsplash.com/photo-1573080496219-bb080dd4f877?w=900&q=85'),
('Concessions','Chicken Nuggets','Crispy chicken nuggets with dipping sauce',15.00,'Sides','https://images.unsplash.com/photo-1562967914-608f82629710?w=900&q=85'),
('Concessions','Soft Drink','Chilled canned soft drink',7.00,'Cold drinks','https://images.unsplash.com/photo-1543255006-d6395b6f1171?w=900&q=85');

update public.menu_items m
set description=c.description,price_myr=c.price,category=c.category,image_url=c.image_url
from jdt_menu_catalogue c join public.vendors v on v.name=c.vendor_name
where m.vendor_id=v.id and m.name=c.name;

insert into public.menu_items(vendor_id,name,description,price_myr,category,image_url)
select v.id,c.name,c.description,c.price,c.category,c.image_url
from jdt_menu_catalogue c join public.vendors v on v.name=c.vendor_name
where not exists(select 1 from public.menu_items m where m.vendor_id=v.id and m.name=c.name);

drop table jdt_menu_catalogue;
