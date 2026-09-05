-- Sample cricket shop catalogue for every club (idempotent by name+club).

INSERT INTO products (club_id, name, description, price_cents, currency, category, stock, active)
SELECT c.id, v.name, v.description, v.price_cents, 'GBP', v.category::product_category, v.stock, TRUE
FROM clubs c
CROSS JOIN (
    VALUES
        -- Bats & blades
        ('Gray-Nicolls Gn4 English Willow Bat', 'Grade 2 English willow, mid-weight match bat.', 18900, 'equipment', 12),
        ('SS Soft Touch Kashmir Willow Bat', 'Club / junior practice bat.', 4500, 'equipment', 20),
        -- Balls
        ('Dukes County Special Ball (red)', 'Match-quality red leather ball.', 2800, 'equipment', 40),
        ('Kookaburra Club Match Pink Ball', 'Pink leather for day/night friendlies.', 3200, 'equipment', 24),
        ('Training Soft Ball (pack of 6)', 'Indoor / nets soft balls.', 1800, 'equipment', 30),
        -- Protective kit
        ('GM Diamond Batting Pads', 'Adult RH pads, lightweight foam.', 6500, 'equipment', 15),
        ('New Balance DC 1080 Batting Gloves', 'Adult RH gloves with fibre inserts.', 4200, 'equipment', 18),
        ('Masuri Vision Series Helmet', 'Titanium grille, club colours.', 8900, 'equipment', 10),
        ('Abdo Guard + Box', 'Essential protective kit.', 1200, 'equipment', 50),
        -- Shoes
        ('Asics Gel-Peake Cricket Spike', 'Rubber outsole with replaceable spikes.', 9500, 'merchandise', 16),
        ('Gray-Nicolls Players Rubber Shoe', 'All-rounder rubber sole for artificial.', 7200, 'merchandise', 20),
        -- Sportswear / club kit
        ('Club Playing Shirt (white)', 'Moisture-wicking match shirt — sizes S–XXL.', 3500, 'merchandise', 40),
        ('Club Training Polo (navy)', 'Training / nets polo with crest space.', 2800, 'merchandise', 35),
        ('Club Hoodie', 'Heavyweight cotton blend hoodie.', 4500, 'merchandise', 25),
        ('Club Cap (navy)', 'Structured peak cap.', 1500, 'merchandise', 60),
        ('Playing Trousers (cream)', 'Classic cricket trousers.', 3200, 'merchandise', 30),
        -- Hire
        ('Full Kit Hire (pads + gloves + helmet)', 'Per session hire for guests / juniors.', 800, 'kit_hire', NULL),
        ('Bat Hire (session)', 'Club bat for nets or socials.', 500, 'kit_hire', NULL),
        -- Match-day extras
        ('Match Tea Bundle', 'Tea, coffee & biscuits for the pavilion.', 1500, 'food', NULL),
        ('Electrolyte Drink', '500ml recovery drink.', 250, 'drink', 80)
) AS v(name, description, price_cents, category, stock)
WHERE NOT EXISTS (
    SELECT 1 FROM products p
    WHERE p.club_id = c.id AND p.name = v.name
);
