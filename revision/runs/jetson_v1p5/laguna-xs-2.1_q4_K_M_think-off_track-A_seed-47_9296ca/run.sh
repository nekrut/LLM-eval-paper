#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Reference indexing — BWA
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Reference indexing — samtools faidx
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv

for sample in "${SAMPLES[@]}"; do
    bam_file="results/${sample}.bam"
    bai_file="${bam_file}.bai"
    vcf_gz_file="results/${sample}.vcf.gz"
    vcf_tbi_file="${vcf_gz_file}.tbi"
    
    # Check if all outputs exist and are newer than inputs
    bam_newer=true
    for input in "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz"; do
        if [ "$input" -nt "$bam_file" ]; then
            bam_newer=false
            break
        fi
    done
    
    # BAM file
    if [ ! -f "$bam_file" ] || [ ! -f "$bai_file" ] || [ "$bam_newer" = false ]; then
        bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | samtools sort -@ $THREADS -o "$bam_file" -
        samtools index -@ $THREADS "$bam_file"
    fi
    
    # VCF file
    vcf_tmp="results/${sample}.vcf"
    if [ ! -f "$vcf_gz_file" ] || [ ! -f "$vcf_tbi_file" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf_tmp" "$bam_file"
        bgzip -f -c "$vcf_tmp" > "$vcf_gz_file"
        tabix -p vcf "$vcf_gz_file"
        rm -f "$vcf_tmp"
    fi
    
    # Add to collapsed TSV
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz_file" | awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done