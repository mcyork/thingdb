# Tools Directory

This directory contains comprehensive LLM prompts and documentation for working with the inv2-dev project and Raspberry Pi systems.

## Contents

### 1. `pi-cli-llm-prompt.md`
**Comprehensive guide for the pi CLI tool**
- Command reference and examples
- Best practices and troubleshooting
- Integration patterns and automation
- Security considerations and performance tips

**Use when:**
- Working with the pi CLI tool
- Managing multiple Raspberry Pi devices
- Automating remote Pi operations
- Troubleshooting pi CLI issues

### 2. `raspberry-pi-basics-llm-prompt.md`
**Essential Raspberry Pi administration knowledge**
- System fundamentals and setup
- System administration and maintenance
- Networking and security
- Hardware and GPIO management
- Development and programming

**Use when:**
- Learning Raspberry Pi basics
- System administration tasks
- Troubleshooting Pi issues
- Setting up new Pi devices
- Learning Linux administration on Pi

### 3. `project-workflow-llm-prompt.md`
**Project-specific workflows and deployment**
- Interactive installer system
- Deployment strategies
- Development workflows
- Component management
- Troubleshooting project issues

**Use when:**
- Working with the inv2-dev project
- Deploying components to Pi devices
- Understanding project architecture
- Troubleshooting deployment issues
- Learning project-specific workflows

### 4. `serial-bridge-llm-prompt.md`
**Serial communication and debugging with Serial Bridge**
- Serial Bridge tool architecture (Pi-side agent + Mac-side bridge)
- Serial communication commands and protocols
- Command execution and output parsing
- Raspberry Pi serial integration
- Troubleshooting serial issues

**Use when:**
- Debugging serial communication with Pi
- Running commands on Pi via serial connection
- Testing Pi serial agent functionality
- Troubleshooting Pi serial issues
- Setting up serial debugging workflows

## How to Use These Prompts

### For LLM Assistance
Copy and paste the relevant prompt into your LLM conversation to get expert assistance with:

- **Pi CLI operations**: Use the pi-cli-llm-prompt.md content
- **Raspberry Pi administration**: Use the raspberry-pi-basics-llm-prompt.md content  
- **Project workflows**: Use the project-workflow-llm-prompt.md content
- **Serial debugging**: Use the serial-bridge-llm-prompt.md content

### For Learning and Reference
These prompts serve as comprehensive reference guides for:

- **Developers**: Understanding the project structure and workflows
- **System Administrators**: Managing Raspberry Pi devices
- **DevOps Engineers**: Automating deployment and maintenance
- **Troubleshooters**: Diagnosing and fixing issues

### For Team Onboarding
Use these prompts to:

- **Train new team members** on Pi management
- **Standardize procedures** across the team
- **Document best practices** for future reference
- **Create training materials** for different skill levels

## Prompt Structure

Each prompt follows a consistent structure:

1. **Overview**: High-level explanation of the topic
2. **Core Concepts**: Fundamental knowledge and principles
3. **Command Reference**: Specific commands and examples
4. **Common Use Cases**: Practical applications and workflows
5. **Troubleshooting**: Common issues and solutions
6. **Best Practices**: Recommended approaches and patterns
7. **Integration Examples**: Real-world usage scenarios

## Updating the Prompts

These prompts should be updated when:

- **New features** are added to the project
- **Best practices** evolve based on experience
- **New tools** or workflows are introduced
- **Common issues** are discovered and resolved
- **Team feedback** suggests improvements

## Contributing

To improve these prompts:

1. **Identify gaps** in coverage or clarity
2. **Add examples** from real-world usage
3. **Update commands** for new versions or tools
4. **Include troubleshooting** for new issues
5. **Refine language** for better LLM understanding

## Related Documentation

These prompts complement other project documentation:

- **INSTALL_README.md**: Interactive installer usage
- **DEPLOYMENT_GUIDE.md**: Deployment strategies
- **PROJECT_STRUCTURE.md**: Project organization
- **SOURCE_CODE_ARCHITECTURE.md**: Code structure

## Quick Reference

### Common Commands
```bash
# Check Pi status
pi status

# Deploy components
./install

# Build deployment package
./deploy/deploy-prepare-clean.sh

# Start development environment
./scripts/start-dev.sh

# Test serial communication
python3 scripts/serial_bridge run "pwd" --port_name pi_console

# Monitor serial traffic
python3 scripts/serial_bridge read --port_name pi_console --timeout 5
```

### Key Files
- `./install`: Interactive installer script
- `./deploy/`: Deployment scripts and packages
- `./serial/`: Serial communication components
- `./network/`: Network configuration components

### Essential Workflows
1. **Component Deployment**: Use `./install` for individual components
2. **Full Deployment**: Use deploy scripts for complete system
3. **Development**: Use Docker scripts for local development
4. **Testing**: Use test scripts for validation

These prompts provide comprehensive coverage of all aspects of working with the inv2-dev project and Raspberry Pi systems. Use them to get expert assistance, learn new skills, and standardize procedures across your team.
