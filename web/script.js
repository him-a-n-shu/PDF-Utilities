document.addEventListener('DOMContentLoaded', function() {
    // Navigation functionality
    const navLinks = document.querySelectorAll('.nav-links li');
    const sections = document.querySelectorAll('.tool-section');

    navLinks.forEach(link => {
        link.addEventListener('click', function() {
            const sectionId = this.getAttribute('data-section');
            navLinks.forEach(l => l.classList.remove('active'));
            this.classList.add('active');
            sections.forEach(section => {
                section.classList.add('hidden');
                if (section.id === sectionId) {
                    section.classList.remove('hidden');
                }
            });
        });
    });

    // Set first section as active by default
    navLinks[0].classList.add('active');

    // Form submission handler for other tools
    const forms = document.querySelectorAll('form');
    forms.forEach(form => {
        form.addEventListener('submit', async function(e) {
            e.preventDefault();
            const formData = new FormData(this);
            try {
                const response = await fetch('/process', {
                    method: 'POST',
                    body: formData
                });
                if (!response.ok) throw new Error('Processing failed');
                const blob = await response.blob();
                const url = window.URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = response.headers.get('Content-Disposition')?.split('filename=')[1] || 'output.pdf';
                a.click();
                window.URL.revokeObjectURL(url);
            } catch (error) {
                alert('Error: ' + error.message);
            }
        });
    });

    // Quality range input
    const qualityRange = document.getElementById('img-quality');
    const qualityValue = document.getElementById('quality-value');
    if (qualityRange && qualityValue) {
        qualityRange.addEventListener('input', function() {
            qualityValue.textContent = this.value;
        });
    }
});
