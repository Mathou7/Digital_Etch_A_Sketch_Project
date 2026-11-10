library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library pll;
use pll.all;

entity telecran is
    port (
        -- FPGA
        i_clk_50: in std_logic;

        -- HDMI
        io_hdmi_i2c_scl       : inout std_logic;
        io_hdmi_i2c_sda       : inout std_logic;
        o_hdmi_tx_clk        : out std_logic;
        o_hdmi_tx_d          : out std_logic_vector(23 downto 0);
        o_hdmi_tx_de         : out std_logic;
        o_hdmi_tx_hs         : out std_logic;
        i_hdmi_tx_int        : in std_logic;
        o_hdmi_tx_vs         : out std_logic;

        -- Reset
        i_rst_n : in std_logic;
         
        -- LED
        o_leds : out std_logic_vector(9 downto 0);
        o_de10_leds : out std_logic_vector(7 downto 0);

        -- Encoder
        i_left_ch_a : in std_logic;
        i_left_ch_b : in std_logic;
        i_left_pb : in std_logic;
        i_right_ch_a : in std_logic;
        i_right_ch_b : in std_logic;
        i_right_pb : in std_logic
    );
end entity telecran;

architecture rtl of telecran is

    component I2C_HDMI_Config
        port (
            iCLK        : in std_logic;
            iRST_N      : in std_logic;
            I2C_SCLK    : out std_logic;
            I2C_SDAT    : inout std_logic;
            HDMI_TX_INT : in std_logic
        );
    end component;

    component pll
        port (
            refclk   : in std_logic;
            rst      : in std_logic;
            outclk_0 : out std_logic;
            locked   : out std_logic
        );
    end component;

    constant h_res : natural := 720;
    constant v_res : natural := 480;

    signal s_clk_27 : std_logic;
    signal s_rst_n  : std_logic;

    signal s_x_counter : natural range 0 to h_res - 1;
    signal s_y_counter : natural range 0 to v_res - 1;

    -- Coordonnées du pixel qui bouge commandées par les 2 encodeurs
    signal s_pos_x : integer range 0 to h_res - 1 := h_res / 2;
    signal s_pos_y : integer range 0 to v_res - 1 := v_res / 2;

    -- Signaux venant des composants encodeurs filtrés
    signal s_left_inc  : std_logic;
    signal s_left_dec  : std_logic;
    signal s_right_inc : std_logic;
    signal s_right_dec : std_logic;
     
    -- Signaux pour la mémoire de Dual-Port
    signal s_addr_a : natural range 0 to (h_res * v_res - 1);
    signal s_addr_b : natural range 0 to (h_res * v_res - 1);
    signal s_q_b    : std_logic_vector(7 downto 0);
     
    -- État du stylet (Position écriture ou levé)
    signal r_pen_down : std_logic := '1'; 

    -- Signaux pour l'effacement et le filtrage des boutons
    signal s_clearing       : std_logic := '0';
    signal s_clear_addr     : natural range 0 to (h_res * v_res) := 0;
    signal s_final_addr_a   : natural range 0 to (h_res * v_res - 1);
    signal s_final_data_a   : std_logic_vector(7 downto 0);
    signal s_final_we_a     : std_logic;

    signal s_left_btn_pulse  : std_logic;
    signal s_right_btn_pulse : std_logic;

begin

    o_leds        <= (others => '0');
    o_de10_leds   <= (others => '0');

    -- Horloge de 27 MHz et signal de verrouillage de la PLL
    pll0 : component pll
        port map (
            refclk   => i_clk_50,
            rst      => not i_rst_n,
            outclk_0 => s_clk_27,
            locked   => s_rst_n
        );

    -- Configuration du circuit HDMI
    I2C_HDMI_Config0 : component I2C_HDMI_Config
        port map (
            iCLK        => i_clk_50,
            iRST_N      => i_rst_n,
            I2C_SCLK    => io_hdmi_i2c_scl,
            I2C_SDAT    => io_hdmi_i2c_sda,
            HDMI_TX_INT => i_hdmi_tx_int
        );

    -- Contrôleur des timings du HDMI	 
    hdmi_controler0 : entity work.hdmi_controler
        port map (
            i_clk           => s_clk_27,
            i_rst_n         => s_rst_n,

            o_hdmi_hs       => o_hdmi_tx_hs,
            o_hdmi_vs       => o_hdmi_tx_vs,
            o_hdmi_de       => o_hdmi_tx_de,

            o_pixel_en      => open,
            o_pixel_address => s_addr_b,

            o_x_counter     => s_x_counter,
            o_y_counter     => s_y_counter
        );

    -- Instance de l'encodeur gauche avec Mouvement horizontal s_pos_x
    enc_left : entity work.encodeur
        generic map (
            g_max_value  => h_res - 1,
            g_width      => 10,
            g_div_factor => 50000
        )
        port map (
            i_clk    => s_clk_27,
            i_rst_n  => s_rst_n,
            i_a      => i_left_ch_a,
            i_b      => i_left_ch_b,
            o_inc    => s_left_inc,
            o_dec    => s_left_dec,
            o_count  => open,
            o_leds   => open,
            o_enable => open
        );

    -- Instance de l'encodeur droit avec Mouvement vertical s_pos_y
    enc_right : entity work.encodeur
        generic map (
            g_max_value  => v_res - 1,
            g_width      => 10,
            g_div_factor => 50000
        )
        port map (
            i_clk    => s_clk_27,
            i_rst_n  => s_rst_n,
            i_a      => i_right_ch_a,
            i_b      => i_right_ch_b,
            o_inc    => s_right_inc,
            o_dec    => s_right_dec,
            o_count  => open,
            o_leds   => open,
            o_enable => open
        );

    -- Calcul de l'adresse de dessin (Port A)
    s_addr_a <= s_pos_x + (s_pos_y * h_res);

    -- Mode effacement, mode dessin normal (Multiplexage)
    s_final_addr_a <= s_clear_addr when s_clearing = '1' else s_addr_a;
    s_final_data_a <= x"00" when s_clearing = '1' else x"01";
    s_final_we_a <= '1' when s_clearing = '1' else r_pen_down;

    -- Instance de la mémoire RAM de Dual-Port
    dpram0 : entity work.dpram
        generic map (
            mem_size   => h_res * v_res,
            data_width => 8
        )
        port map (
            i_clk_a  => s_clk_27,
            i_clk_b  => s_clk_27,
            i_data_a => s_final_data_a,
            i_data_b => (others => '0'),
            i_addr_a => s_final_addr_a,
            i_addr_b => s_addr_b,
            i_we_a   => s_final_we_a,
            i_we_b   => '0',
            o_q_a    => open,
            o_q_b    => s_q_b
        );

    -- Filtrage anti-rebond pour le bouton gauche qui q'occupe de l'Effacement
    process(s_clk_27, s_rst_n)
        variable v_div_cnt    : integer range 0 to 49999 := 0;
        variable v_pb_prev    : std_logic := '1';
        variable v_enable_btn : std_logic := '0';
    begin
        if s_rst_n = '0' then
            v_div_cnt        := 0;
            v_enable_btn     := '0';
            v_pb_prev        := '1';
            s_left_btn_pulse <= '0';
        elsif rising_edge(s_clk_27) then
            v_enable_btn     := '0';
            s_left_btn_pulse <= '0';
            if v_div_cnt = 49999 then
                v_div_cnt    := 0;
                v_enable_btn := '1';
            else
                v_div_cnt    := v_div_cnt + 1;
            end if;

            if v_enable_btn = '1' then
                if (i_left_pb = '0' and v_pb_prev = '1') then
                    s_left_btn_pulse <= '1';
                end if;
                v_pb_prev := i_left_pb;
            end if;
        end if;
    end process;

    -- Filtrage anti-rebond pour le bouton droit qui s'occupe de l'état posé/levé du stylet
    process(s_clk_27, s_rst_n)
        variable v_div_cnt    : integer range 0 to 49999 := 0;
        variable v_pb_prev    : std_logic := '1';
        variable v_enable_btn : std_logic := '0';
    begin
        if s_rst_n = '0' then
            v_div_cnt         := 0;
            v_enable_btn      := '0';
            v_pb_prev         := '1';
            s_right_btn_pulse <= '0';
        elsif rising_edge(s_clk_27) then
            v_enable_btn      := '0';
            s_right_btn_pulse <= '0';
            if v_div_cnt = 49999 then
                v_div_cnt     := 0;
                v_enable_btn  := '1';
            else
                v_div_cnt     := v_div_cnt + 1;
            end if;

            if v_enable_btn = '1' then
                if (i_right_pb = '0' and v_pb_prev = '1') then
                    s_right_btn_pulse <= '1';
                end if;
                v_pb_prev := i_right_pb;
            end if;
        end if;
    end process;

    -- Gestion de l'effacement de l'écran déclenché par le bouton gauche
    process(s_clk_27, s_rst_n)
    begin
        if s_rst_n = '0' then
            s_clearing   <= '0';
            s_clear_addr <= 0;
        elsif rising_edge(s_clk_27) then
            if s_clearing = '1' then
                if s_clear_addr = (h_res * v_res - 1) then
                    s_clearing   <= '0';
                    s_clear_addr <= 0;
                else
                    s_clear_addr <= s_clear_addr + 1;
                end if;
            else
                if s_left_btn_pulse = '1' then
                    s_clearing   <= '1';
                    s_clear_addr <= 0;
                end if;
            end if;
        end if;
    end process;

    -- Gestion du mode du stylet déclenché par le bouton droit (Levé/Posé)
    process(s_clk_27, s_rst_n)
    begin
        if s_rst_n = '0' then
            r_pen_down <= '1';
        elsif rising_edge(s_clk_27) then
            if s_right_btn_pulse = '1' then
                r_pen_down <= not r_pen_down;
            end if;
        end if;
    end process;

    -- Mise à jour des positions du pixel à partir des impulsions filtrées
    process(s_clk_27, s_rst_n)
    begin
        if s_rst_n = '0' then
            s_pos_x <= h_res / 2;
            s_pos_y <= v_res / 2;
        elsif rising_edge(s_clk_27) then
            -- Mouvement horizontal avec l'encodeur de gauche
            if s_left_inc = '1' then
                if s_pos_x < h_res - 1 then
                    s_pos_x <= s_pos_x + 1;
                end if;
            elsif s_left_dec = '1' then
                if s_pos_x > 0 then
                    s_pos_x <= s_pos_x - 1;
                end if;
            end if;

            -- Mouvement vertical avec l'encodeur de droite
            if s_right_inc = '1' then
                if s_pos_y < v_res - 1 then
                    s_pos_y <= s_pos_y + 1;
                end if;
            elsif s_right_dec = '1' then
                if s_pos_y > 0 then
                    s_pos_y <= s_pos_y - 1;
                end if;
            end if;
        end if;
    end process;

    -- Horloge et données vidéo HDMI
    o_hdmi_tx_clk <= s_clk_27;

    -- Affichage du curseur en noir, le tracé en rouge et le fond en blanc
    o_hdmi_tx_d <= x"000000" when (s_x_counter = s_pos_x and s_y_counter = s_pos_y) else
                   x"FF0000" when s_q_b /= x"00" else 
                   x"FFFFFF";

end architecture rtl;