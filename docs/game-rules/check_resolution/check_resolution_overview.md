# Checks

An action that can potentially fail requires rolling a **check**. There are several different types of **checks**: Attribute Checks, Aptitude Checks, Saving Throw Checks, Opposed Aptitude Checks, Spell Checks, and Combat Checks. Each **check** involves rolling a number of <Die Size> sided dice.

# Dice Cap

Each **check** involves rolling between <Dice Minimum> and <Dice Minimum - Dice Range - 1> dice. The number of dice is calculated using a creature's attribute value in the most appropriate attribute to the **check**, and the creature's **prowess**. These two values are used to calculate the **dice cap** using this formula: <Dice Cap Formula>.
 
%% Tests %% 
- Global 
	- <Dice Minimum> = 3
	- <Dice Range> = 5
	- Attribute Contribution Formula = "<Attribute> / 2"
	- Dice Cap Formula: "<Minimum Dice> + ((<Attribute Contribution Formula> + <Prowess>) % <Dice Range>)"

- Where 
	- Attribute Value = 0 
	- Prowess = 10 
- Expected
	- Dice Cap = 3

- Where 
	- Attribute Value = 10 
	- Prowess = 0 
- Expected
	- Dice Cap = 3

- Where 
	- Attribute Value = 2 
	- Prowess = 10 
- Expected
	- Dice Cap = 4

- Where 
	- Attribute Value = 10 
	- Prowess = 2 
- Expected
	- Dice Cap = 5

- Where 
	- Attribute Value = 10 
	- Prowess = 4 
- Expected
	- Dice Cap = 7
%% Test %% 

# Dice Modifier

Each **check** involves rolling dice against a **target number**. The Base Target number is <Base Target Number> and that number is adjusted by any bonuses or penalties that are applied to the **check**. Each bonus and penalty has a type and bonuses and penalties of the same type do not stack. Only the highest bonus and the most severe penalty of each type are applied. The unbound dice modifier is calculated by adding the highest bonus of each type and subtracting the most severe penalty of each type. 
 
%% Tests %% 
- Where 
	- Bonus List = {"Circumstance": 4, "Circumstance": 2} 
	- Penaly List = {} 
- Expected
	- Dice Modifier = +4

- Where 
	- Bonus List = {} 
	- Penaly List = {"Circumstance": 4, "Circumstance": 2} 
- Expected
	- Dice Modifier = -4

- Where 
	- Bonus List = {} 
	- Penaly List = {} 
- Expected
	- Dice Modifier = +0

- Where 
	- Bonus List = {"Circumstance": 2, "Guidance": 1} 
	- Penaly List = {"Circumstance": 4, "Guidance": 2} 
- Expected
	- Dice Modifier = -3

- Where 
	- Bonus List = {"Circumstance": 5, "Guidance": 1} 
	- Penaly List = {"Circumstance": 4, "Circumstance": 2} 
- Expected
	- Dice Modifier = +2
%% Test %% 

# Starting Value

The **target number** for a **check** cannot go below <Minimum Target Number> or exceed <Maximum Target Number> and whenever the bonuses are penalties for a **check** would push the **target number** out of bounds the **starting value** is incremented or decremented. The formula for calculating the **starting value** is min(0, <Minimum Target Number> - Dice Modifier) - min(0, Dice Modifier - <Maximum Target Number>)
 
%% Tests %% 
- Global 
	- <Minimum Target Number> = 3
	- <Maximum Target Number> = 9

- Where 
	- Dice Modifer = 10 
- Expected
	- Starting Value = -1

- Where 
	- Dice Modifer = -2 
- Expected
	- Starting Value = +5

- Where 
	- Dice Modifer = 5
- Expected
	- Starting Value = +0
%% Test %% 

# Check Target Number

Once you have calculated the Dice Modifer, we can calculate the **target number** for the **check**. This is calculated by taking the Base Target Number (<Base Target Number>) adding the Dice Modifer. If the sum is less then the minimum target number (<Minimum Target Number>) then the Check Target Number is <Minimum Target Number>. If the sum is greater then the maximum target number (<Maximum Target Number>) then the check target number is <Maximum Target Number>.


- **Degree of Success** — Sum of Supporting DoIS minus sum of Opposing DoIS. Its negative magnitude is the **Degree of Failure**.
- **Check Outcome** — `success`, `failure`, or `fumble`, classified from the Degree of Success against the dice resolution thresholds. A Check can always Fumble.
- **Spread Check** — An area-effect Check (`spread: true`): prepared like any other, but the Supporting total nets against **each** Opposing Roll independently — one Outcome per caught creature.

# Check Competency Bonus

This is calculated using the <Competency Bonus Formula>

# Attribute Checks

These are the most basic checks and involve simple tasks that do not benefit from training such as pushing something heavy, or attempting to remember something you heard earlier. First you must calculate the Dice Cap using the appropriate attribute and using 0 for prowess. You apply an inherent bonuses from your tier, and a competence bonus from Check Competency Bonus.


# Aptitude Checks
# Saving Throw Checks
# Opposed Aptitude Checks
# Spell Checks
# Combat Checks
