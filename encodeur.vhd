library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity encodeur is
    generic (
        g_max_value  : integer := 9;   
        g_width      : integer := 4;   
        g_div_factor : integer := 50000
    );
    port(
        i_clk    : in  std_logic;
        i_rst_n  : in  std_logic;
        i_a      : in  std_logic;
        i_b      : in  std_logic;
        o_inc    : out std_logic;
        o_dec    : out std_logic;
        o_count  : out std_logic_vector(g_width - 1 downto 0);
        o_leds   : out std_logic_vector(9 downto 0);
        o_enable : out std_logic
    );
end entity encodeur;

architecture rtl of encodeur is

    signal r_a_prev : std_logic := '0';
    signal r_count  : integer range 0 to g_max_value := 0;
   
    signal r_div_cnt : integer range 0 to g_div_factor - 1 := 0;
    signal s_enable  : std_logic := '0';

begin

    --Diviseur de fréquence
    process(i_clk, i_rst_n)
    begin
        if i_rst_n = '0' then
            r_div_cnt <= 0;
            s_enable  <= '0';
        elsif rising_edge(i_clk) then
            s_enable <= '0';
            if r_div_cnt = g_div_factor - 1 then
                r_div_cnt <= 0;
                s_enable  <= '1';
            else
                r_div_cnt <= r_div_cnt + 1;
            end if;
        end if;
    end process;

    o_enable <= s_enable;

    --Processus principal
    process(i_clk, i_rst_n)
    begin
        if i_rst_n = '0' then
            r_a_prev <= '0';
            r_count  <= 0;
            o_inc    <= '0';
            o_dec    <= '0';
        elsif rising_edge(i_clk) then
            o_inc <= '0';
            o_dec <= '0';

            if s_enable = '1' then
                r_a_prev <= i_a;

                if (i_a = '1' and r_a_prev = '0') then
                    if (i_b = '0') then
                        o_inc <= '1';
                        if r_count = g_max_value then
                            r_count <= 0;
                        else
                            r_count <= r_count + 1;
                        end if;
                    else
                        o_dec <= '1';
                        if r_count = 0 then
                            r_count <= g_max_value;
                        else
                        r_count <= r_count - 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Sortie binaire du compteur
    o_count <= std_logic_vector(to_unsigned(r_count, g_width));

    -- Décodage pour allumer une seule LED à la fois
    process(r_count)
    begin
        o_leds <= (others => '0');
        o_leds(r_count) <= '1';
    end process;

end architecture rtl;