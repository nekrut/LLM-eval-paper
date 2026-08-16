#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing — BWA (check if already indexed)
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Reference indexing — samtools faidx (check if already indexed)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    bam_file="results/${sample}.bam"
    vcf_file="results/${sample}.vcf"
    vcf_gz_file="results/${sample}.vcf.gz"
    
    # Alignment and sorting (check if BAM exists)
    if [ ! -f "$bam_file" ]; then
        bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ $THREADS -o "$bam_file" -
    fi
    
    # BAM index (check if BAI exists)
    if [ ! -f "${bam_file}.bai" ]; then
        samtools index -@ $THREADS "$bam_file"
    fi
    
    # Variant calling with LoFreq (check if VCF.gz exists)
    if [ ! -f "$vcf_gz_file" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf_file" "$bam_file"
        bcftools view -Oz -o "$vcf_gz_file" "$vcf_file"
        tabix -p vcf "$vcf_gz_file"
    fi
done

# Create collapsed TSV (check if exists)
if [ ! -f results/collapsed.tsv ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
fi

for sample in "${SAMPLES[@]}"; do
    vcf_gz_file="results/${sample}.vcf.gz"
    if [ -f "$vcf_gz_file" ]; then
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz_file" | awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
    fi
done