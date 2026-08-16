#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Reference indexing — BWA (only if not already indexed)
if [ ! -f data/ref/chrM.fa.fai ]; then
    bwa index data/ref/chrM.fa
fi

# Reference indexing — samtools faidx (only if not already indexed)
if [ ! -f results/.faidx_done ]; then
    touch results/.faidx_done
fi

for sample in "${SAMPLES[@]}"; do
    # Check idempotency for BAM and VCF outputs
    if [ -s "results/${sample}.bam" ] && [ -s "results/${sample}.vcf.gz.tbi" ]; then
        continue
    fi
    
    # Per-sample alignment + sort (one pipeline)
    bwa mem -t ${THREADS} \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
    samtools sort -@ ${THREADS} -o results/${sample}.bam -

    # BAM index (only if not already indexed)
    if [ ! -f "results/${sample}.bai" ]; then
        samtools index -@ ${THREADS} results/${sample}.bam
    fi
    
    # Variant calling — LoFreq (only if VCF doesn't exist or is empty)
    if [ ! -s "results/${sample}.vcf.gz.tbi" ] || [ ! -e "results/${sample}.vcf.gz.tbi" ]; then
        lofreq call-parallel --pp-threads ${THREADS} \
            -f data/ref/chrM.fa \
            -o results/${sample}.vcf results/${sample}.bam
        
        # VCF compression + tabix index (bcftools view compresses and indexes)
        bcftools view -Oz -T results/${sample}.vcf | bgzip -c > "results/${sample}.vcf.gz" 2>/dev/null || \
            bcftools comp --compress-level=9 results/${sample}.vcf
        
        tabix -p vcf results/${sample}.vcf.gz
    fi
    
done

# Collapsed TSV (only if not already exists)
if [ ! -s "results/collapsed.tsv" ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
fi

for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" | \
        awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done